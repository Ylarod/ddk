import sys
from elftools.elf.elffile import ELFFile
from struct import unpack_from, pack


def load_module_symvers(path: str):
    result = {}
    with open(path, "r") as f:
        content = f.read()
    arr = content.split("\n")
    for one in arr:
        try:
            crc, name = one.split(" ")
            result[name] = crc
        except ValueError:
            pass
    return result


def load_ko_symvers(path: str):
    result = []
    file = open(path, 'rb')
    elf_file = ELFFile(file)
    section = elf_file.get_section_by_name("__versions")
    data = section.data()
    start = section.header['sh_offset']
    size = section.header['sh_size']
    count = int(size / 64)
    # print(size)
    # print(count)
    for i in range(count):
        addr = i * 64
        crc, = unpack_from("<I", data, addr)
        symbol, = unpack_from("56s", data, addr + 8)
        symbol = symbol.decode("utf-8").rstrip("\0")
        result.append((start + addr, hex(crc), symbol))
    return result


def compare_symvers(module_symvers, ko_symvers):
    loadable = True
    for i in ko_symvers:
        module_crc = module_symvers[i[2]]
        if module_crc != i[1]:
            print("Different:", i[2], i[1], module_crc)
            loadable = False
    return loadable


def modify_ko_symvers(path, module_symvers, ko_symvers):
    with open(path, "rb") as f:
        data = f.read()
        data = bytearray(data)
    for i in ko_symvers:
        module_crc = module_symvers[i[2]]
        if module_crc != i[1]:
            addr = int(i[0])
            crc = pack("<I", int(module_crc, 16))
            data[addr] = crc[0]
            data[addr + 1] = crc[1]
            data[addr + 2] = crc[2]
            data[addr + 3] = crc[3]
            print(i[2], i[1], "=>", module_crc)
    with open(path, "wb") as f:
        f.write(data)


def main():
    if len(sys.argv) != 3:
        print("Usage: loadable.py [ko] [kernel_symvers]")
        return
    ko_symvers = load_ko_symvers(sys.argv[1])
    kernel_symvers = load_module_symvers(sys.argv[2])
    if compare_symvers(kernel_symvers, ko_symvers):
        print("Loadable")
    else:
        print("Not loadable")


if __name__ == "__main__":
    main()
