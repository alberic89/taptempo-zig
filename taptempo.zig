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
//! Compilé avec succès avec zig 0.11.0 (4 août 2023)
//! Retouvez le code source à <https://github.com/alberic89/taptempo-zig>
//
// Pour compiler :
// ```bash
// zig build-exe taptempo.zig
// ```
//
// Usage :
// ```bash
// ./taptempo [nombre_de_frappe]
// ```
// 
// Par défaut, le nombre de frappe est de 5
// 
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
/// Peut retourner une erreur, sinon retourne le tempo dans un u64
pub fn captureTempo(tty: fs.File) !u64 {

    // On prépare l'allocateur
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator();

    // On récupère le deuxième argument de la ligne de commande,
    // et on donne sa valeur à NB_FRAPPE_T si on le peut sinon 5
    var args = std.process.args();
    _ = args.next();
    const NB_FRAPPE_T = std.fmt.parseInt(u8, args.next() orelse "5", 10) catch 5;

    // On initialise une array de la taille NB_FRAPPE_T en s'assurant
    // que la mémoire sera libérée
    var tap: []i64 = try allocator.alloc(i64, NB_FRAPPE_T);
    defer allocator.free(tap);

    // On enregistre NB_FRAPPE_T frappes
    var NB_FRAPPE: u8 = 0;
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
            NB_FRAPPE += 1;
            try stdout.print(".", .{});
        }
    }
    try stdout.print(" Terminé.\n", .{});

    // Si il y a eu moins de 2 frappes réelles, on ne peut pas calculer le tempo
    if (NB_FRAPPE < 2) {
        try stdout.print("Pas assez de frappes.\n", .{});
        return 0;
    }

    var ecart: []i64 = try allocator.alloc(i64, NB_FRAPPE - 1);
    defer allocator.free(ecart);

    // On calcule l'écart entre les frappes
    for (1..NB_FRAPPE) |i| {
        ecart[i - 1] = tap[i] - tap[i - 1];
    }
    var ecart_moy: f64 = 0;
    // On calcule l'écart moyen
    for (ecart) |e| {
        ecart_moy += @as(f64, @floatFromInt(e));
    }
    ecart_moy /= @as(f64, @floatFromInt(ecart.len));
    // Le tempo est donné avec un entier en battements par minute
    var bpm: u64 = @intFromFloat((60 * time.ms_per_s) / ecart_moy);
    try stdout.print("Tempo : {} bpm\n", .{bpm});
    return bpm;
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
        "Bienvenue dans TapTempo !\nPour commencer, appuyez sur une touche.\n(q pour arrêter)\n",
        .{});

    while (true) {
        var buffer: [1]u8 = undefined;
        _ = try tty.read(&buffer);
        if (buffer[0] == 'q') {
            break;
        } else {
            _ = try captureTempo(tty);
        }
    }
    try stdout.print("Au revoir !\n", .{});
    // Restaure l'état original du terminal
    try os.tcsetattr(tty.handle, .FLUSH, original);
    return;
}
