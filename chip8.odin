package chip8

import "core:fmt"
import rand "core:math/rand"
import "core:os"
import "core:time"
import SDL "vendor:sdl2"

CHIP8_FONT_SET :: []u8{ 
  0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
  0x20, 0x60, 0x20, 0x20, 0x70, // 1
  0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
  0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
  0x90, 0x90, 0xF0, 0x10, 0x10, // 4
  0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
  0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
  0xF0, 0x10, 0x20, 0x40, 0x40, // 7
  0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
  0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
  0xF0, 0x90, 0xF0, 0x90, 0x90, // A
  0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
  0xF0, 0x80, 0x80, 0x80, 0xF0, // C
  0xE0, 0x90, 0x90, 0x90, 0xE0, // D
  0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
  0xF0, 0x80, 0xF0, 0x80, 0x80, // F
}

Emulator :: struct {
    opcode: u16,
    memory: [4092]u8,
    graphics: [64 * 32]u8,
    registers: [16]u8,
    index: u16,
    pc: u16,
    
    delay_timer: u8,
    sound_timer: u8,
    
    stack: [16]u16,
    sp: u16,

    keys: [16]u8,

    rng: rand.Rand,

    window: ^SDL.Window,
    renderer: ^SDL.Renderer,
    texture: ^SDL.Texture,
}

initialize :: proc(emu: ^Emulator) -> bool {
    // Emulator initialization
    emu.rng = rand.create(u64(time.to_unix_seconds(time.now())))
    emu.pc = 0x200

    for r, i  in CHIP8_FONT_SET {
        emu.memory[i] = r
    }

    if SDL.Init({.VIDEO, .AUDIO, .EVENTS}) < 0 {
        fmt.println("Unable to initialize SDL2: %v\n", SDL.GetErrorString())
        return false
    }

    emu.window = SDL.CreateWindow("CHIP-8 Emulator", SDL.WINDOWPOS_CENTERED, SDL.WINDOWPOS_CENTERED,
    1024, 512, SDL.WindowFlags{})
    if emu.window == nil {
        fmt.println("Unable to create SDL2 window: %v\n", SDL.GetErrorString())
        return false
    }

    emu.renderer = SDL.CreateRenderer(emu.window, -1, SDL.RENDERER_ACCELERATED)
    if emu.renderer == nil {
        fmt.printf("Unable to create SDL2 renderer: %v\n", SDL.GetErrorString())
        return false
    }

    emu.texture = SDL.CreateTexture(emu.renderer, u32(SDL.PixelFormatEnum.RGBA8888), .STREAMING, 64, 32)
    if emu.texture == nil {
        fmt.printf("Unable to create SDL2 texture: %v\n", SDL.GetErrorString())
        return false
    }

    fmt.println("Emulator initialized")
    return true
}

destroy :: proc(emu: ^Emulator) {
    SDL.DestroyTexture(emu.texture)
    SDL.DestroyRenderer(emu.renderer)
    SDL.DestroyWindow(emu.window)
    SDL.Quit()
}

load :: proc(emu: ^Emulator, filename: ^string) -> bool {
    f, err := os.open(filename^)
    if err != os.ERROR_NONE {
        fmt.printf("Unable to load file: %v\n", err)
        return false
    }
    defer os.close(f)

    data, success := os.read_entire_file(f)
    if !success {
        fmt.printf("Unable to read file: %v\n", filename)
        return false
    }
    defer delete(data)

    for b,i in data {
        emu.memory[i + 0x200] = b
    }

    return true 
}

cycle :: proc(emu: ^Emulator) {
    emu.opcode = u16(emu.memory[emu.pc]) << 8 | u16(emu.memory[emu.pc + 1])
    ms_nib := emu.opcode >> 12

    switch ms_nib {
        case 0x0:
            op := emu.opcode & 0x00FF
            switch op {
                case 0xE0:
                    for _, i in emu.graphics {
                        emu.graphics[i] = 0
                    }
                case 0xEE:
                    if emu.sp > 0 {
                        emu.sp -= 1
                        emu.pc = emu.stack[emu.sp]
                    }
            }

            increment_pc(emu)
        case 0x1: // JMP
            emu.pc = emu.opcode & 0x0FFF
        case 0x2: // CALL addr
            emu.stack[emu.sp] = emu.pc
            emu.sp += 1
            emu.pc = emu.opcode & 0x0FFF
        case 0x3: // Skip next instruction if regX == byte
            x := (emu.opcode & 0x0F00) >> 8
            val := u8(emu.opcode) & 0x00FF

            if emu.registers[x] == val {
                increment_pc(emu)
            }

            increment_pc(emu)
        case 0x4: // Skip next instruction if regX != byte
            x := (emu.opcode & 0x0F00) >> 8
            val := u8(emu.opcode & 0x00FF)

            if emu.registers[x] != val {
                increment_pc(emu)
            }

            increment_pc(emu)
        case 0x5: // Skip next instruction if regX == regY
            x := (emu.opcode & 0x0F00) >> 8
            y := (emu.opcode & 0x00F0) >> 4

            if emu.registers[x] == emu.registers[y] {
                increment_pc(emu)
            }

            increment_pc(emu)
        case 0x6: // LD regX = byte
            x := (emu.opcode & 0x0F00) >> 8
            val := u8(emu.opcode & 0x00FF)

            emu.registers[x] = val

            increment_pc(emu)
        case 0x7: // ADD regX + byte
            x := (emu.opcode & 0x0F00) >> 8
            val := u8(emu.opcode & 0x00FF)

            emu.registers[x] += val

            increment_pc(emu)
        case 0x8: // Multiple Apps
            x := (emu.opcode & 0x0F00) >> 8
            y := (emu.opcode & 0x00F0) >> 4
            op := emu.opcode & 0x000F

            switch op {
                case 0x0: // LD regX = regY
                    emu.registers[x] = emu.registers[y]
                case 0x1: // OR regX | regY
                    emu.registers[x] |= emu.registers[y]
                case 0x2: // AND regX & regY
                    emu.registers[x] &= emu.registers[y]
                case 0x3: // XOR regX ^ regY
                    emu.registers[x] ~= emu.registers[y]
                case 0x4: // ADD regX + regY
                    result := u16(emu.registers[x]) + u16(emu.registers[y])
                    emu.registers[0xF] = 1 if result > 255 else 0 
                    emu.registers[x] = u8(result)
                case 0x5: // SUB regX - regY
                    emu.registers[0xF] = 1 if emu.registers[x] > emu.registers[y] else 0
                    emu.registers[x] -= emu.registers[y]
                case 0x6: // Shift Right
                    emu.registers[0xF] = 1 if emu.registers[x] % 2 != 0 else 0
                    emu.registers[x] = emu.registers[x] >> 1
                case 0x7: // SUBN regY - regX
                    emu.registers[0xF] = 1 if emu.registers[y] > emu.registers[x] else 0
                    emu.registers[x] = emu.registers[y] - emu.registers[x]
                case 0xE: // Shift Left
                    emu.registers[0xF] = 1 if emu.registers[x] & 0xF0 != 0 else 0
                    emu.registers[x] = emu.registers[x] << 1
                }
            increment_pc(emu)
        case 0x9: //Skip next instruction if regX != regY
            x := (emu.opcode & 0x0F00) >> 8
            y := (emu.opcode & 0x00F0) >> 4

            if emu.registers[x] != emu.registers[y] {
                increment_pc(emu)
            }

            increment_pc(emu)
        case 0xA: // Set I = nnn
            n := emu.opcode & 0x0FFF
            emu.index = n
            increment_pc(emu)
        case 0xB: // JMP to nnn + reg0
            n := emu.opcode & 0x0FFF
            emu.pc = n + u16(emu.registers[0x0])
            increment_pc(emu)
        case 0xC: // RND regX = rand + n
            x := (emu.opcode & 0x0F00) >> 8
            n := u8(emu.opcode & 0x00FF)
            r := u8(rand.uint32(&emu.rng))

            emu.registers[x] = n & r

            increment_pc(emu)
        case 0xD: // DRW n-byte sprite starting at memory location I at (regX, regY), set regF = collision
            x := emu.registers[(emu.opcode & 0x0F00) >> 8]
            y := emu.registers[(emu.opcode & 0x00F0) >> 4]
            height := emu.opcode & 0x000F
            pixel : u8 = 0 

            emu.registers[0xF] = 0
            for y_line : u16 =0; y_line < height; y_line += 1 {
                pixel = emu.memory[emu.index + y_line]

                for x_line : u16 = 0; x_line < 8; x_line += 1 {

                    if (pixel & (0x80 >> x_line)) != 0 {
                        gfx_loc := u16(x) + x_line + ((u16(y) + y_line) * 64)
                        if gfx_loc < 2048 {
                            if (emu.graphics[gfx_loc] == 1) {
                                emu.registers[0xF] = 1
                            }
                            emu.graphics[gfx_loc] ~= 1
                        }
                    }
                } 
            }

            increment_pc(emu)
        case 0xE:
            x := (emu.opcode & 0x0F00) >> 8
            op := emu.opcode & 0x00FF
            switch op {
                case 0x9E: // Skip next instruction if key is pressed
                    if emu.keys[emu.registers[x]] != 0 {
                        increment_pc(emu)
                    }
                case 0xA1: // Skip next instruction if key is NOT pressed
                    if emu.keys[emu.registers[x]] == 0 {
                        increment_pc(emu)
                    }
            }

            increment_pc(emu)
        case 0xF:
            x := (emu.opcode & 0x0F00) >> 8
            op := u8(emu.opcode) & 0x00FF

            switch op {
                case 0x07:
                    emu.registers[x] = emu.delay_timer
                case 0x0A:
                    key_pressed := false

                    for k, i in emu.keys {
                        if k != 0 {
                            emu.registers[x] = u8(i)
                            key_pressed = true
                            break
                        }
                    }

                    if !key_pressed {
                        return
                    }
                case 0x15:
                    emu.delay_timer = emu.registers[x]
                case 0x18:
                    emu.sound_timer = emu.registers[x]
                case 0x1E:
                    emu.index += u16(emu.registers[x])
                case 0x29:
                    if emu.registers[x] < 16 {
                        emu.index = u16(emu.registers[x] * 0x5)
                    }
                case 0x33:
                    emu.memory[emu.index] = emu.registers[x] / 100
                    emu.memory[emu.index + 1] = (emu.registers[x] / 10) % 10
                    emu.memory[emu.index + 2] = emu.registers[x] % 10 
                case 0x55:
                    for i : u16 = 0; i <= x; i += 1 {
                        emu.memory[emu.index + i] = emu.registers[i]
                    }
                case 0x65:
                    for i : u16 = 0; i <= x; i += 1 {
                        emu.registers[i] = emu.memory[emu.index + i]
                    }
            }

            increment_pc(emu)
        case:
            fmt.printf("Unknown opcode: %v\n", emu.opcode)
    }

    if emu.delay_timer > 0 {
        emu.delay_timer -= 1
    }
    if emu.sound_timer > 0 {
        // Actually play sound!
        fmt.printf("Beep!\n")
        emu.sound_timer -= 1
    }
    

}

increment_pc :: proc(emu: ^Emulator) {
    emu.pc += 2
}