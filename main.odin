package chip8

import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"
import SDL "vendor:sdl2"


update_texture :: proc(emu: ^Emulator) {
    tex_data : rawptr
    pitch : i32 = 0

    SDL.LockTexture(emu.texture, nil, &tex_data, &pitch)
    
    data : []u32 = slice.from_ptr(cast([^]u32)tex_data, len(emu.graphics))
    for p, i in emu.graphics {
        data[i] = 0x00000000 if p == 0 else 0xFFFFFFFF
    }

    SDL.UnlockTexture(emu.texture)
}

setup_key :: proc(key_map: ^map[SDL.Keycode]u8) {
    key_map[SDL.Keycode.X] = 0
    key_map[SDL.Keycode.NUM1] = 1
    key_map[SDL.Keycode.NUM2] = 2
    key_map[SDL.Keycode.NUM3] = 3
    key_map[SDL.Keycode.Q] = 4
    key_map[SDL.Keycode.W] = 5
    key_map[SDL.Keycode.E] = 6
    key_map[SDL.Keycode.A] = 7
    key_map[SDL.Keycode.S] = 8
    key_map[SDL.Keycode.D] = 9
    key_map[SDL.Keycode.Z] = 0xA
    key_map[SDL.Keycode.C] = 0xB
    key_map[SDL.Keycode.NUM4] = 0xC
    key_map[SDL.Keycode.R] = 0xD
    key_map[SDL.Keycode.F] = 0xE
    key_map[SDL.Keycode.V] = 0xF
}

main :: proc() {

    key_map := make(map[SDL.Keycode]u8)
    defer delete(key_map)

    setup_key(&key_map)

    if len(os.args) < 2 {
        fmt.println("Please provide a rom to load!")
        return
    }

    rom := os.args[1]

    emu := Emulator{}
    if !initialize(&emu) {
        fmt.println("Unable to setup emulator")
        return
    }
    defer destroy(&emu)

    if !load(&emu, &rom) {
        return
    }

    for quit := false; !quit; {
        cycle(&emu)

        for event: SDL.Event; SDL.PollEvent(&event); {
            // Update to take keypresses
            #partial switch event.type {
            case .QUIT:
                quit = true
            case .KEYDOWN:
                if event.key.keysym.sym == .ESCAPE {
                    quit = true
                }

                key, ok := key_map[event.key.keysym.sym]
                if ok {
                    emu.keys[key] = 1
                }
            case .KEYUP:
                key, ok := key_map[event.key.keysym.sym]
                if ok {
                    emu.keys[key] = 0
                }
            }

        }

        SDL.RenderClear(emu.renderer)
        update_texture(&emu)

        dest := SDL.Rect{0, 0, 1024, 512}
        SDL.RenderCopy(emu.renderer, emu.texture, nil, &dest)
        SDL.RenderPresent(emu.renderer)

        time.sleep(16000000)
    }
}