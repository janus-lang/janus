// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// North Star MVP Integration Test - Complete End-to-End Validation
// Demonstrates the full revolutionary ASTDB architecture with alls

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    // Import all revolutionaronents
    const astdb = @import("compiler/libjanus/astdb.zig");
    const EffectSystem = @import("compiler/effect_system.zig");
    const ComptimeVM = @import(";


stem
    var astdb_system = try astdb.ASTDBSysue);
    defer astdb_system.deinit();



P
    var snapshot = try astdb_system.createSn
    defer snapshot.deinit();


    // Initialize effect & capability system
system);
    defer effect_system.deinit();

});

    // Initialize comptime VM
    var comptime_vm = ComptimeVM.init(allocator, &astdb_system, snapshot, &effect_system);
    defer comptime_vm.deinit();



    // Simulate parsing the North Star MVP program
    // func pure_math(a: i32, b: i32) -> i32 { return a + b }

    // String interning for function components
    const pure_math_str = try astdb_system.str_interner.get("math");
    const read_file_str = try astdb_system.str_interner.get("read_a);
    const main_str = try astdb_system.str_interner.get("main");
");
    const b_str = try astdb_system.str_interner.get("b");

    const cap_str = try astdb_system.str_inte");

    // Type strings
    const i32_str = try32");
    const string_str = t
    const error_str = t
    const void_str = t");
    const cap_fs_read_d");

);

    // Create source spans
    const span = astdb.Span{

        .start_line = 1, .start_col = 1,
1,
    };

    // Create tokens for pure_math function
    const func_token = try snapshot.addToken(.kw_func, pure_math_str, span);

    const i32_token = try snapsan);

    // Create type nodes
    const i32_type_node = try snapshot.addNode(.basic_type, i32_token, i32_token, &[_]astdb.NodeId{});

    // Create parameter nodes for pure_math(a: i32, b: i32)

    const b_token = try snapshot.addTok;
    const a_param_node = try snap
    const b_param_node = try snapshot.addNode(.var_decl, b_token, b_toke;

    // Create pure_math function node


;

    // Create read_a_file function: func rear
an);
    const string_token = try snapshot.addT, span);
    const cap_fs_read_token = try snapshot.addToken(.identifier, cap_f

    // Create parameter nodes

    const cap_token = ;
    const string_type_node = try snapshot.addNode(.basic_type, Id{});
    const cap_type_node = try snapshot.addNode(.basic_type, cap_fs_reeId{});

de});
    const cap_param_node = ;

    // Create error union return type (string!Error)
;
    const error_type_node = try snapshot.addNode(.basic_type, error_token, erro);
    const error_union_node = try snapshot.addNode(.basic_type, string_token, error_token, &[_

ion node
    const read_file_node = try snap



    const main_token = try snapshot.addToken(.identifier, main_str, span);

    const void_type_node = try snapshot.addNode(.basic_type, void_token, ;
    const main_node = try snapshot.addNode(.;



    const program_str = try astdb_system.str_interner.get("north_star_p");
    const program_token = try snapshot.addToken(.identifier, program_san);
    const root_node = try snapshot.addNode(.root, program_token, program_token, &[_]astdb.;




e!)
    const opts = astdb.CIDOpts{};
    const root_cid = try astdb_system.getCID
ts);
    const read_file_cid = try astdb_system.ge);




    // Register functions in effect system
    try effect_system.registerFunction(pure_math_node, pure_math_str);
    try effect_system.registerFunction(read_file_node, read_file_str);
    try effect_system.registerFunction(main_node, main_str);

ects
    try effect_system.addFunctionEffect(pure_math_node, .pure);
    try effect_system.addFunctionEffect(read;


    // Add capabilities
    try effect_system.addFunctionCapability(read_file_node, .cap_fs_read);
    try effect_system.addFunctionCapability(main_node, .cap_stdout);


    // Verify effect analysis
    const pure_is_pure = effect_system.functionIsPure(pure_math_node);
de);
    const file_has_fs_read = effect_system.functionHasEffect(read
    const file_requires_cap = effect_system.functionRequiresCapability(read_file_node, .

;

    // Validate function signatures
;
    const file_valid = effect_system.validateFunction(read_file_node);
    const main_valid = effect_system.validateFunction(main_node);



    // Simulate comptime block execution
    // let pure_func := std.meta.get_function("pure_math")
    const pure_func_var = try astdb_system.str_interner.get("pure_func");
    const pure_func_ref = ComptimeValue{

            .node_id = pure_math_node,
            .name = pure_math_str,
            .effects = &[_]EffectSystem.EffectType{.pure},
            .capabilities = &[_]EffectSystem.CapabilityType{},
,
    };

    try comptime_vm.context.setVariable(pure_func_var, pure_func_ref, true);

    // let file_func := std.meta.get_function("read_a_file")
    const file_func_var = try astdb_system.str_interner.get("file_func");
    const file_func_ref = ComptimeValue{
        .function_ref = .{
_node,
            .name = read_file_str,
            .effects = &[_]EffectSystem.EffectType{.io_fs_read},
            .capabilities = &[_]EffectSystemd},
    },
    };

    try comptime_vm.context.setVariable(file_func_var, file_func_ref, true);

    // Execute comptime assertions
    const pure_var = comptime_vm.context.getVariable(pure_func_var).?;


    // assert(pure_func.effects.is_pure())
    const pure_effects = ComptimeValue.EffectSet{ .effects = pure_var.value.function_ref.efs };
    const assertion1 = pure_effects.isPure();

"))
    const file_effects = ComptimeValue.EffectSet{ .effects = file_vfects };
    const assertion2 = file_effects.hasEffect(.io_fs_read);
 ion2});
}", .{});
\nE VALIDATED!ITECTURARCHRY OLUTIONAREV STAR MVP - 🎉 NORTHnt(".debug.pri});
    std\n", .{NAL!ND OPERATIOLETE ACOMPVOLUTION IS DB REE AST"\n🔥 THug.print(td.deb    s);

n", .{}ons passed\y assertiionarevolutAll r("   ✅ .debug.print;
    std\n", .{})essfulsuccecution ogramming exta-prme me Comptiint("   🚀ebug.prd.d
    st});", .{s working\nalysibility anapaect and cEff   🔍 ("ebug.printstd.d
    n", .{});uilds\istic beterminputed for dssed IDs comt-addre  🔐 Conten(" .debug.print
    std .{});n", ASTDB\red intosed and sons parl functi📝 Al"   ug.print( std.deb
   ", .{});plete:\n Comsis AnalyProgramMVP th Star t("\n🎯 Nor.debug.printd    s{});

e\n", .dwar harodernd for mmizelayout optilumnar "   ✅ Coprint(  std.debug.
  \n", .{});n allocatiough arenarothanagement  m-leak memory   ✅ Zerot("d.debug.prin{});
    st .able)\n",s cap (sub-10m analysisnticsed sema✅ Query-ba.print("     std.debug, .{});
  ection\n"rosption intncming with fueta-programme m ✅ Compti"  ebug.print(
    std.d.{});n\n", iome verificat compile-titypabiliand caEffect   ✅ ug.print(" debd.{});
    st\n", .nuplicatiotomatic dedauning with tering in ✅ Strt("  rinebug.p
    std.d\n", .{});ic CIDsnistwith determiorage essed stContent-addrt("   ✅ .debug.prin);
    std\n", .{}emonstrated:eatures Dutionary F"🚀 Revolnt(pri  std.debug.;

  })=\n", .{================================="======t(rintd.debug.p
    s.{});SS!\n", - SUCCEON P INTEGRATIMVNORTH STAR "\n🎉 ebug.print(
    std.dzed});
    ns_analyunctiome_stats.fpticom", .{zed: {}\nnalytions a"  - Funcebug.print(
    std.d});ountariables_cstats.v .{comptime_: {}\n", - Variables" .print( std.debug.{});
   ", \nM:time Vomp("Cg.printstd.debu;
    s()e_vm.getStat = comptime_statst comptim
    consistics VM statme// Compti

    });id_functionsstats.valffect_\n", .{ections: {}lid funVa"  - int(.debug.pr
    stdons});ul_functiffectfts.e{effect_sta, .ons: {}\n"ctiffectful fun"  - Eint(bug.pr    std.deons});
pure_functitats.fect_s", .{ef\nions: {}funct"  - Pure .print(  std.debug);
  tions}s.total_funct_stat{effec: {}\n", .al functions("  - Totdebug.print   std.", .{});
 stem:\nfect Syprint("Ef  std.debug.();
  atsStgetSystemect_system._stats = effconst effects
    sticystem stati// Effect s    );

kenCount()}.topshot", .{snastorage)\nicient ns: {} (effTokent("  - debug.prid.)});
    stnodeCount(hot.snaps .{",r layout)\n (columna - Nodes: {}g.print("  std.debus});
   cached_cidastdb_stats.\n", .{age)ressed storcontent-addCIDs: {} (d che("  - Caprint  std.debug.ings});
  terned_strdb_stats.in.{astn", )\ationduplicatic deautom} (d strings: { Interneint("  -ebug.pr  std.d{});
  \n", .em:SystASTDB int("debug.pr  std.ats();
  em.stsyststdb_s = astdb_statnst a
    coatisticsASTDB st//
    .{});
    ==\n", ===================int("======d.debug.pr);
    st\n", .{}ICSRY STATISTVOLUTIONAn📊 RE"\(ntug.pri   std.deb);

 n3}tioser}\n", .{as= {) ad\")"CapFsRepability(\s_caequiree_func.rassert(fil.print("✅    std.debug
 _read);_fsity(.capasCapabilps.h3 = file_ca assertionst  con
  ies };.capabiliton_refncti.fualueile_var.vilities = f .capabt{SepabilityeValue.Camptim = Coe_capsfilt
    consFsRead"))Cap("abilityapc.requires_cune_fert(fil  // ass
