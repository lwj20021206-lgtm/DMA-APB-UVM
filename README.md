# DMA-APB UVM 验证工程

本工程验证一个带 direct access、DMA INIT/COPY 和中断状态寄存器的 APB 设备。

## 目录

- `apb_device.v`：DMA/APB DUT
- `src/`：APB master/slave agent、interrupt handler、driver、monitor、sequencer、item 和 sequence
- `apb_device_src/apb_device_scoreboard.sv`：寄存器、下游传输顺序和 reference memory 检查
- `apb_device_src/apb_device_coverage_full.sv`：完整功能覆盖率模型
- `apb_device_src/apb_device_env.sv`：agent、scoreboard 和 coverage 的连接
- `test.sv`：UVM test
- `top.sv`：仿真顶层
- `filelist.f`：编译文件表

## 中断调度

Master monitor 观察 `apb_device_int` 的边沿。中断到来后，高优先级
`apb_interrupt_sequence` 会在当前 APB 事务完成的边界取得 sequencer，读取
`DMA_INT`，再按读回状态执行 W1C。已经进入 setup/access 的事务不会被中途打断。

## Scoreboard检查内容

- direct read/write 的下游地址、方向和数据；
- DMA INIT/COPY 的下游传输数量、顺序、地址及数据；
- SRC/DST/LEN 寄存器模型；
- 下游 reactive memory 的读写结果；
- invalid-op、invalid-length、overlap、done 状态和 W1C 清除；
- 仿真结束时无遗留传输、COPY 数据或未处理中断。

## VCS运行

```sh
make compile
make run TEST=test SEED=1
```

或直接执行：

```sh
vcs -full64 -sverilog -ntb_opts uvm-1.2 \
  -debug_access+all -cm line+cond+tgl+fsm+branch \
  -f filelist.f -o simv
./simv +UVM_TESTNAME=test +ntb_random_seed=1 \
  -cm line+cond+tgl+fsm+branch -l sim.log
```

定义 `FSDB` 宏后才会调用 FSDB dump 系统任务。DUT 原有的固定事务自检已经放在
`APB_DEVICE_LEGACY_SELFTEST` 宏下，默认由 UVM scoreboard 负责检查。

本机也使用 Accellera UVM 源码和 Verilator 对完整工程做过 lint；Verilator 会忽略
部分 covergroup bins，因此正式功能覆盖率请使用 VCS、Xcelium 或 Questa 收集。
