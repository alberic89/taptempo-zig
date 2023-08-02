// taptempo.zig
//
//! Copyright 2023 alberic89 <alberic89@gmx.com>
//!
//! This program is free software; you can redistribute it and/or modify
//! it under the terms of the GNU General Public License as published by
//! the Free Software Foundation; either version 3 of the License, or
//! (at your option) any later version.
//!
//! This program is distributed in the hope that it will be useful,
//! but WITHOUT ANY WARRANTY; without even the implied warranty of
//! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//! GNU General Public License for more details.
//!
//! You should have received a copy of the GNU General Public License
//! along with this program. If not, see <https://www.gnu.org/licenses/>. 
//!
//! Compilé avec succès avec zig 0.11.0-dev.4406+d370005d3 (2 août 2023)
//! Retouvez le code source à <https://github.com/alberic89/taptempo-zig>
//
// Pour compiler :
// ```bash
// zig build-exe taptempo.zig
// ```
// Sur une idée de François Mazen
// https://linuxfr.org/users/mzf/journaux/un-tap-tempo-en-ligne-de-commande
//
// Merci à Leon Henrik Plickat pour son exemple d'application zig "Uncooked"
// https://zig.news/lhp/want-to-create-a-tui-application-the-basics-of-uncooked-terminal-io-17gm
//

const std = @import("std");
const stdout = std.io.getStdOut().writer();
const fs = std.fs;
const os = std.os;
const time = std.time;

/// Cette fonction va capturer et calculer le tempo de la frappe au clavier.
/// Peut retourner une erreur.
pub fn captureTempo(tty: fs.File) !void {
    // On enregistre 5 frappes
    var tap: [5]?i64 = [5]?i64{null, null, null, null, null};
    try stdout.print("Capture du tempo", .{});
    for (tap, 0..) |_, index| {
        var buffer: [1]u8 = undefined;
        _ = try tty.read(&buffer);
        // Si la touche q est pressée, on arrête d'enregistrer la frappe
         if (buffer[0] == 'q') {
            break;
        } else {
            // La précision d'enregistrement est *au maximum* de l'ordre
            // de la milliseconde, mais peut être plus faible en fonction
            // du matériel et de l'OS
            tap[index] = time.milliTimestamp();
            try stdout.print(".", .{});
        }
    }
    try stdout.print(" Terminé.\n", .{});
    var ecart: [4]?i64 = [4]?i64{null, null, null, null};
    // On calcule l'écart entre les frappes, en prévoyant le cas où il
    // n'y a pas eu 5 frappes
    for (tap[1..], 0..) |ftime, index| {
        if (ftime != null) {
            ecart[index] = ftime.? - tap[index].?;
        }
    }
    var ecart_moy: ?f64 = null;
    // On calcule l'écart moyen
    for (ecart) |inter| {
        if (inter != null) {
            if (ecart_moy != null) {
                var inter_f: f64 = @floatFromInt(inter.?);
                ecart_moy = ( ecart_moy.? + inter_f ) / 2;
            } else {
                ecart_moy = @floatFromInt(inter.?);
            }
        }
    }
    // Si il y a eu moins de 2 frappes, on ne peut pas calculer le tempo
    if (ecart_moy == null) {
        try stdout.print("Tu n'as pas le rythme dans la peau !\n", .{});
        return;
    }
    // Le tempo est donné avec un entier en battements par minute
    var bpm: u64 = @intFromFloat((60 * time.ms_per_s) / ecart_moy.?);
    try stdout.print("Tempo : {} bpm\n", .{bpm});
    return;
}

pub fn main() !void {
    // On récupère la sortie standart
    var tty = try fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
    defer tty.close();

    // On enregistre l'état du terminal
    const original = try os.tcgetattr(tty.handle);
    var raw = original;

    // On active un certain nombre de paramètres :
    //   ECHO: Le terminal n'affiche plus les touches pressées.
    // ICANON: Désactive le mode d'entrée canonique ("cooked").
    //         Permet de lire l'entrée byte-par-byte au lieu de
    //         ligne-par-ligne.
    raw.lflag &= ~@as(
        os.linux.tcflag_t,
        os.linux.ECHO | os.linux.ICANON,
    );
    // BRKINT: Désactive la conversion de l'envoi de SIGNINT en cas de crash.
    //         N'as normalement pas d'effet sur les systèmes modernes.
    //  INPCK: Désactive le contrôle de la parité.
    //         N'as normalement pas d'effet sur les systèmes modernes.
    // ISTRIP: Désactive la suppression du 8ème bit des caractères.
    //         N'as normalement pas d'effet sur les systèmes modernes.
    raw.iflag &= ~@as(
        os.linux.tcflag_t,
        os.linux.BRKINT | os.linux.INPCK | os.linux.ISTRIP,
    );

    // On met la taille des caractères à 8 bits.
    // N'as normalement pas d'effet sur les systèmes modernes.
    raw.cflag |= os.system.CS8;

    raw.cc[os.system.V.TIME] = 0;
    raw.cc[os.system.V.MIN] = 1;

    // Applique les changements
    try os.tcsetattr(tty.handle, .FLUSH, raw);

    try stdout.print(
        "Bienvenue dans Taptempo !\nPour commencer, appuyez sur une touche.\n(q pour arrêter)\n",
        .{});

    while (true) {
        var buffer: [1]u8 = undefined;
        _ = try tty.read(&buffer);
        if (buffer[0] == 'q') {
            break;
        } else {
            try captureTempo(tty);
        }
    }
    try stdout.print("Au revoir !\n", .{});
    // Restaure l'état original du terminal
    try os.tcsetattr(tty.handle, .FLUSH, original);
    return;
}
