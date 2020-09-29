#include <asm.h>

# Start the CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00.
#.set 伪指令
#.code16 下边的代码用16位模式运行
#.code32 下边的代码用32位模式运行
#.global关键字用来让一个符号对链接器可见，可以供其他链接对象模块使用。
#.global _start 让_start符号成为可见的标示符，这样链接器就知道跳转到程序中的什么地方并开始执行。linux寻找这个 _start标签作为程序的默认进入点。
#
#在汇编和C混合编程中，在GNU ARM编译环境下，汇编程序中要使用.global伪操作声明汇编程序为全局的函数，意即可被外部函数调用，同时C程序中要使用extern声明要调用的汇编语言程序。
#
#.extern XXXX 说明xxxx为外部函数，调用的时候可以遍访所有文件找到该函数并且使用它。
.set PROT_MODE_CSEG,        0x8                     # kernel code segment selector
.set PROT_MODE_DSEG,        0x10                    # kernel data segment selector
.set CR0_PE_ON,             0x1                     # protected mode enable flag

# start address should be 0:7c00, in real mode, the beginning address of the running bootloader
.globl start
start:
.code16                                             # Assemble for 16-bit mode
    cli                                             # Disable interrupts
    cld                                             # String operations increment
    
    # b 1byte w 2byte l 4byte q 8byte
	# ah 8-15 al 0-7 
	# ax,bx,cx,dx 是通用16位寄存器，为了兼容上代8位寄存器，分别分为ah,al;bh,bl;ch,cl;dh, dl
	# cs, ds, es, ss 都是段寄存器，存储的都是要指定的一段开始的内存单元地址 
	# xorw 两个字节的ax 寄存器值自己进行异或
	# movw 把ds寄存器的数值拷贝到ax寄存器
	# ss sp 任何时候ss:sp 都指向栈顶元素
	# 
	# 这个设置好像没啥用啊？不都是由后边赋值给前边吗，这个操作好像没什么用处
    # Set up the important data segment registers (DS, ES, SS).
    xorw %ax, %ax                                   # Segment number zero
    movw %ax, %ds                                   # -> Data Segment
    movw %ax, %es                                   # -> Extra Segment
    movw %ax, %ss                                   # -> Stack Segment

    # Enable A20:
	# 只有jmp才能修改cs和ip中的数值，mov不能修改段寄存器和指令寄存器的数值
    #  For backwards compatibility with the earliest PCs, physical
    #  address line 20 is tied low, so that addresses higher than
    #  1MB wrap around to zero by default. This code undoes this.
seta20.1:
    inb $0x64, %al                                  # Wait for not busy
    testb $0x2, %al
    jnz seta20.1

    movb $0xd1, %al                                 # 0xd1 -> port 0x64
    outb %al, $0x64

seta20.2:
    inb $0x64, %al                                  # Wait for not busy
    testb $0x2, %al
    jnz seta20.2

    movb $0xdf, %al                                 # 0xdf -> port 0x60
    outb %al, $0x60

    # Switch from real to protected mode, using a bootstrap GDT
    # and segment translation that makes virtual addresses
    # identical to physical addresses, so that the
    # effective memory map does not change during the switch.
    lgdt gdtdesc
    movl %cr0, %eax
    orl $CR0_PE_ON, %eax
    movl %eax, %cr0

    # Jump to next instruction, but in 32-bit code segment.
    # Switches processor into 32-bit mode.
    ljmp $PROT_MODE_CSEG, $protcseg
#call 
.code32                                             # Assemble for 32-bit mode
protcseg:
    # Set up the protected-mode data segment registers
    movw $PROT_MODE_DSEG, %ax                       # Our data segment selector
    movw %ax, %ds                                   # -> DS: Data Segment
    movw %ax, %es                                   # -> ES: Extra Segment
    movw %ax, %fs                                   # -> FS
    movw %ax, %gs                                   # -> GS
    movw %ax, %ss                                   # -> SS: Stack Segment

    # Set up the stack pointer and call into C. The stack region is from 0--start(0x7c00)
    movl $0x0, %ebp
    movl $start, %esp
    call bootmain

    # If bootmain returns (it shouldn't), loop.
spin:
    jmp spin

.data
# Bootstrap GDT
.p2align 2                                          # force 4 byte alignment
gdt:
    SEG_NULLASM                                     # null seg
    SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)           # code seg for bootloader and kernel
    SEG_ASM(STA_W, 0x0, 0xffffffff)                 # data seg for bootloader and kernel

gdtdesc:
    .word 0x17                                      # sizeof(gdt) - 1
    .long gdt                                       # address gdt
