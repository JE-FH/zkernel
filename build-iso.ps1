zig build
if ($LASTEXITCODE -ne 0) {
    exit 1
}
mkdir -p isodir/boot/grub
cp zig-out/bin/kernel.elf isodir/boot/kernel.elf
cp grub.cfg isodir/boot/grub/grub.cfg
wsl grub-mkrescue -o kernel.iso isodir