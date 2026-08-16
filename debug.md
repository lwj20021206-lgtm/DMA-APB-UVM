# DMA-APB Debug 记录：连续 COPY 指令

> 本文件专门记录“第一次 DMA COPY 运行期间，CPU 发出第二条 COPY，但第一次 COPY 结束后没有再次观察到 `dma_copy_active_p1/p2`”这一波形问题。分析基于当前 `apb_device.v`，并使用原始 RTL 做了最小对照仿真。

## 1. 波形现象

观察到的大致过程为：

```text
CPU发送第一条COPY
        ↓
等待pready_delay减到0
        ↓
上游PREADY拉高，第一条COPY命令完成APB握手
        ↓
dma_copy_active_p1/p2开始运行
        ↓
CPU发出第二条COPY
        ↓
由于is_dma_busy=1，第二条COPY保持PSEL/PENABLE并等待
        ↓
第一条COPY完成，PREADY再次拉高
        ↓
波形中没有再次看到dma_copy_active_p1/p2
```

最初需要确认的问题是：第二条 COPY 是否被 busy 逻辑直接丢弃。

## 2. 正常 COPY 启动条件

COPY 命令的地址译码为：

```verilog
assign is_dma_copy =
    psel & (paddr[31:28] == DMA_COPY) & (pwrite == 1);
```

`dma_copy_active_p1` 的启动条件为：

```verilog
always @(posedge pclk or negedge presetn) begin
    if (~presetn)
        dma_copy_active_p1 <= 0;
    else if (is_dma_copy && pready == 1)
        dma_copy_active_p1 <= 1;
    else if (dma_copy_active_p2 && slave_pready == 1 && dma_len > 1)
        dma_copy_active_p1 <= 1;
    else if (dma_copy_active_p1 && slave_pready == 1)
        dma_copy_active_p1 <= 0;
end
```

从这段主功能逻辑看，只要第二条 COPY 一直保持到 `PREADY=1`，它本来应该在后续时钟沿重新拉高 `dma_copy_active_p1`。

## 3. `PREADY` 为什么会等待第一条 COPY 完成

非 direct-read 的上游响应条件是：

```verilog
else if (!is_dma_read && psel && penable &&
         pready_delay == 0 && !is_dma_busy)
    pready <= 1;
```

第一条 COPY 运行时 `is_dma_busy=1`，所以第二条事务不能立即获得 `PREADY`。APB master 必须保持第二条事务的：

```text
PSEL、PENABLE、PADDR、PWRITE、PWDATA
```

第一条 COPY 最后一次下游传输完成后，`is_dma_busy` 解除，第二条事务才满足上游 `PREADY` 条件。

这里的 `PREADY` 只有在当前存在 `PSEL && PENABLE` 时才会产生，所以它不是单独的 DMA-done 输出；它本来应当作为当前第二条 APB 事务的响应。

## 4. 实际根因：DUT 内置自检执行 `$finish`

DUT 在文件末尾保存上一笔已完成 APB 事务的地址：

```verilog
always @(posedge pclk or negedge presetn) begin
    if (~presetn)
        pre_addr <= 0;
    else if (psel && penable && pready)
        pre_addr <= paddr;
end
```

同时存在一段禁止前 10 笔随机事务连续访问相同完整地址的自检：

```verilog
always @(*) begin
    if (random_cnt != 0 && random_cnt < 11)
    if (psel && penable && pready)
    if (paddr == pre_addr) begin
        $display(
            "Simulation Failed. Address of APB-transfer[%0d] "
            "is the same with address of APB-transfer[%0d].",
            random_cnt+1, random_cnt
        );
        $finish;
    end
end
```

如果两条 COPY 使用相同的完整地址，例如：

```text
第一条COPY：PADDR = 32'h8000_0000
第二条COPY：PADDR = 32'h8000_0000
```

那么第一条命令握手后：

```text
pre_addr = 32'h8000_0000
```

第二条 COPY 在 busy 期间一直保持相同地址。第一条 COPY 结束、`PREADY` 再次变成 1 时，自检条件同时成立：

```text
random_cnt != 0
random_cnt < 11
PSEL && PENABLE && PREADY
PADDR == pre_addr
```

于是自检立即执行 `$finish`。

## 5. 为什么波形中看不到第二次 P1/P2

关键在于 `PREADY` 使用非阻塞赋值，而地址重复检查使用组合逻辑：

```text
第一条COPY最后一次下游传输完成
        ↓
is_dma_busy变成0
        ↓
时钟沿执行 pready <= 1
        ↓
NBA更新后，PREADY在当前仿真时刻变成1
        ↓
always @(*) 地址重复检查立即重新执行
        ↓
发现第二条PADDR == pre_addr
        ↓
立即执行$finish
        ↓
仿真没有机会进入下一个posedge
        ↓
is_dma_copy && pready无法在时钟沿启动第二次P1
```

因此看到的是：

```text
PREADY最后拉高
P1/P2没有再次拉高
波形在该位置结束
```

这不是主 copy 状态机正常地丢弃了第二条命令，而是 DUT 内嵌的测试逻辑提前终止了仿真。

日志中应当能找到：

```text
Simulation Failed. Address of APB-transfer[N]
is the same with address of APB-transfer[N-1].
```

## 6. 最小对照仿真结果

使用当前原始 `apb_device.v`，依次配置 SRC、DST、LEN，然后连续两次写相同 COPY 地址，能够复现：

```text
第一条COPY：P1/P2正常运行
第一条COPY结束：第二条事务对应的PREADY出现
随后打印Address ... is the same ...
RTL执行$finish
第二条P1/P2没有出现
```

屏蔽这段地址重复自检后，使用相同激励可以观察到：

```text
第二条COPY获得PREADY
下一拍dma_copy_active_p1 = 1
随后dma_copy_active_p2 = 1
```

这证明 busy/PREADY 主路径本身会接受第二条 COPY；当前波形中状态没有重新启动的直接原因是 `$finish`。

## 7. 独立的第二个问题：`dma_len` 已经变成 0

第一条 COPY 每完成一次目标写操作都会执行：

```verilog
else if ((dma_init_active || dma_copy_active_p2) && slave_pready)
    dma_len <= dma_len - 1;
```

所以第一条 COPY 全部完成后：

```text
dma_len = 0
```

即使屏蔽 `$finish` 并成功启动第二条 COPY，如果 CPU 没有重新配置 `DMA_LEN`，第二次任务也不会按照原来的长度正常复制。最小仿真中第二条 COPY 只经历了一次 P1/P2，然后 `dma_len` 从 0 下溢为 31。

因此正确启动另一条独立 COPY 前，应重新配置需要的寄存器：

```text
写DMA_SRC
写DMA_DST
写DMA_LEN
写DMA_COPY
```

## 8. Debug 时应检查的信号

遇到相同现象时，建议同时查看：

| 信号 | 检查内容 |
|---|---|
| `paddr`、`pre_addr` | 两条 COPY 的完整 32 bit 地址是否相同 |
| `random_cnt` | 第二条事务发生时是否位于 `1～10` |
| `psel/penable/pready` | `$finish` 条件是否同时成立 |
| 仿真日志 | 是否出现 `Address ... is the same ...` |
| `dma_len` | 第一条 COPY 后是否已经减到 0 |
| `is_dma_copy` | 第二条握手期间地址和 `pwrite` 是否仍能正确译码 |
| `dma_copy_active_p1/p2` | 仿真是否在下一时钟沿到来前已经结束 |

如果两条 COPY 的完整 `paddr` 不同，或者 `random_cnt` 不在 `1～10`，则上述地址重复自检不会触发，需要继续检查 `is_dma_copy`、`pwrite`、复位和仿真日志中的其他 `$finish` 条件。

## 9. 后续处理建议

### 临时验证方法

- 查看日志确认是否由地址重复检查结束仿真。
- 为了观察状态机，可暂时让两个 COPY 使用不同的低 28 bit 地址；DUT 只使用 `paddr[31:28]` 译码，因此它们仍然会被识别为 COPY。
- 第二次 COPY 前重新配置 SRC、DST 和 LEN。

### 正式优化方向

- 将 `random_cnt/pre_addr/golden_data/$finish` 等面向特定测试流程的检查从 DUT 中移出。
- 把这些检查放入 UVM scoreboard、test 或 assertion，避免验证逻辑改变 DUT 的功能行为。
- 如果规格允许连续 DMA 命令，进一步定义 busy 期间的排队、拒绝或等待机制。

---

# 第二部分：代码走读发现的 Bug 与疑点清单

> 整理于 2026-08-16。来源：对 `apb_device.v` 及 UVM 环境（scoreboard / sequencer / interrupt handler / env / coverage）的通读分析。
> 分类：A. RTL Bug（含已确认与推演待验证）；B. RTL 疑点/风格；C. 验证环境问题。
> 推演结论均附定向验证方法，验证前在 testplan 中保持 Planned 状态。

## A. RTL Bug

### BUG-01：`invalid_value_of_length` 缺少 `pwrite` 判断（已确认）

- **位置**：`apb_device.v:140`
- **现象**：读 DMA_LEN 时 `pwdata` 无功能含义，若残留值 >16（上一笔写遗留），会误触发 invalid-length 中断。
- **影响**：scoreboard 按"仅写触发"建模，该场景一旦出现即 mismatch；软件侧收到虚假中断。
- **状态**：已记录于 [后续优化方案.md](./后续优化方案.md) 优化项 1（含修复代码）。
- **验证**：定向测试——写 LEN=17（触发一次中断并清除）后读 DMA_LEN，观察 `dma_int[2]` 是否再次置位。

### BUG-02：LEN=1 的 INIT/COPY 被 direct 尾单的完成拍误杀（推演，待验证）

- **位置**：状态机 `apb_device.v:184-211`、选择器 `:300-331`、装载器 `:273-286`
- **机制**：状态机的完成条件只认 `slave_pready`，不区分"这笔完成属于谁"：
  - **LEN=1 INIT** + direct 尾单挂起：尾单完成拍满足 `init_active && slave_pready && dma_len==1` → `dma_init_active` 清零、`dma_len` 1→0；选择器 INIT 分支 `!(dma_len==1 & slave_pready)` 同时失效 → 落到 else 分支 → 总线回空闲。**INIT 一笔传输都没发就结束，但 done 中断照常置位**（`dma_init_copy_done` 当拍为 1）。
  - **LEN=1 COPY** + 尾单挂起：尾单完成拍被当成读相位完成 → `p2` 启动、读被跳过，写出去的是 `dma_init_value` 中的陈旧数据。
- **前提窗口**：BUSY-04 的豁免④ 使 INIT/COPY 能在 direct 尾单挂起期间被接受（见 BUG-03）。
- **scoreboard 捕捉能力**（恰好都能抓）：INIT 丢失 → 预期队列残留 → check_phase 报 "expected downstream transfers did not complete"；COPY 跳读 → 第一笔 actual（写）对预期（读）方向 mismatch；中断侧 model 与 RTL 不一致 → DMA_INT 读回 mismatch。
- **验证**：定向测试——慢 slave（大 ready_delay）挂起 direct 尾单 + 发 LEN=1 INIT/COPY，观察下游是否发出传输、done 是否误置。
- **建议**：在 testplan BUSY-006/007 附近单列测试点，设计评审确认修复方向（完成条件需识别传输归属）。

### BUG-03：`is_dma_busy` 豁免④ 的危险窗口（推演）

- **位置**：`apb_device.v:122`
- **机制**：`dma_direct_active & !slave_pready` 豁免使 INIT 启动后、尾单结账前 busy=0 → 上游配置写（SRC/DST/LEN）可完成握手 → **在 INIT 第一笔尚未发出时改写 `dma_src/dma_len`，正在排队的 DMA 被改配置**。
- **矛盾点**：同样的配置写，只要尾单一完成（busy 回到 1）就会被挡到整个 DMA 结束——挡不挡得住取决于一笔无关的 direct 尾单有没有结账。
- **不对称**：COPY 读相位（p1）无此豁免，同场景发 COPY 时上游被挡死，行为不一致。
- **状态**：待设计评审，可并入 SPEC-TBD-05（busy 语义）。

### BUG-04：同拍 W1C 与新事件竞争，新事件丢失（推演，待验证）

- **位置**：`apb_device.v:144-149`
- **机制**：`dma_int_nxt` 组合逻辑中 W1C 分支优先；W1C 与新事件同拍成立时只做 `dma_int & ~pwdata`，不并入 `dma_int_update`。done / invalid 类事件多为单拍脉冲，一旦丢失不可恢复。
- **影响**：Testplan INT-010；随机流量下撞拍概率大增 → scoreboard 预期与 RTL 实际不一致 → 偶发 mismatch，极难定位。
- **验证**：定向测试——COPY 最后一笔完成拍同时发 W1C，检查 done 是否丢失。
- **建议**：设计评审确定优先级（通常新事件不应被 W1C 吞掉，`dma_int_nxt = (dma_int & ~pwdata) | dma_int_update` 是常见修法）。

## B. RTL 疑点 / 风格问题

| 编号 | 位置 | 内容 |
|---|---|---|
| SUS-01 | `apb_device.v:122` | `is_dma_busy` 表达式优先级完全靠默认规则（`!` > `&` > `|`），无括号，意图难读。建议加括号或改写 |
| SUS-02 | `apb_device.v:280` | 装载条件中 `is_dma_write` 被 `!is_dma_busy` 管了两次（内层 + 外层），读方向只被外层管一次；功能等价于 `(is_dma_read \| is_dma_write) & !is_dma_busy & !dma_direct_active`。多次修改叠出来的痕迹 |
| SUS-03 | `apb_device.v:144-149、:258-266` | `dma_int_nxt` / `prdata_nxt` 组合逻辑无默认赋值，工具会推断锁存器；当前被时序更新 guard 挡住未见明显错误，建议补默认值 |
| SUS-04 | `apb_device.v:50、:65` | `MEM[0:1023]`、`int_status` 声明后从未使用；TB 侧 `apb_master_item.ready_delay`、`apb_slave_item.addr_delay` 也未使用。保留作扩展或清理 |
| SUS-05 | `apb_device.v:138` | done 中断每笔下游完成都置位（SPEC-TBD-01），非仅最后一笔；当前 scoreboard 按此建模，待规格确认 |

## C. 验证环境问题（TB）

| 编号 | 位置 | 内容 | 修法建议 |
|---|---|---|---|
| TB-01 | `apb_device_scoreboard.sv` | scoreboard 无 reset 建模：中途注入 reset 后预期队列 / 中断模型 / reference memory / model_src/dst/len 不清空 → check_phase 全是假错 | 加 reset 回调（与 `reset_inject_phase` knob 配套实现，见 [覆盖率bin分析与随机模型规划.md](../覆盖率bin分析与随机模型规划.md) §5.3） |
| TB-02 | `apb_interrupt_handler.sv:22` | `interrupt_pending` 竞争窗口：handler 清 pending 与 monitor 置新 pending 竞争 → 中断丢失 → `wait_for_next_interrupt` 挂死到 1ms timeout。定向测试碰不到，随机流量必现 | 清 pending 前重新检查电平，或改为"计数 + 电平"双状态 |
| TB-03 | `apb_device_env.sv:58` | `reset_phase` 只在仿真开始时执行一次，环境无中途注入 reset 能力 → `cg_reset` 的 during_setup / during_access bins 不可达，RST-002~004 无法执行 | 加 `reset_inject_phase` knob |
| TB-04 | 根目录 `apb_device.v` | 根目录旧版 DUT 的 legacy 自检未用 `ifdef` 包裹，谁用谁复现第一部分记录的 `$finish` 问题；权威版本为 `DMA-APB/apb_device.v` | 删除或同步根目录旧文件 |

## D. 关联文档

- [后续优化方案.md](./后续优化方案.md)：BUG-01 的修复代码与验证补充
- [DMA_APB_Verification_Testplan.md](./DMA_APB_Verification_Testplan.md)：SPEC-TBD-03/05、INT-010、BUSY-006/007、RST-002~004
- [../覆盖率bin分析与随机模型规划.md](../覆盖率bin分析与随机模型规划.md)：TB-01/02/03 的加固计划与面试防守要点

