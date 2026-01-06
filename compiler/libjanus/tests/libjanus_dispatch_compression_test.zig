// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

 }
}     }
   ster
   ould be faion shress// Decomp; me < 5.0)s_ti_decompresct(avgxpetesting.e     try
       y fastblasonaould be re// Sh; .0)ime < 10s_tmpres_coxpect(avgy testing.e     trn
       ressiomp cohieve some/ Should ac; / 1.0)ratio <sion_t(compresng.expectitesry      t
       none) {backend != .      if (  ed)
s as needoldthreshons (adjust ce assertierforman   // P

       );     }0)
   / 1000.ress_time  (avg_comp4.0) /102 / 1024.0 / ms.len))_data.ite(testnttFromIloaf64, @fas((@          )", .{
  compression (2} MB/sghput: {d:.rouo("  Thinftd.log.
        sn_ratio});ssiocompre, .{d:.3}"ion ratio: {pressfo("  Comintd.log.       s);
 ssed_size}vg_compre{a} bytes", .sed size: {rage compreso("  Ave.inf  std.log    });
  ess_timempr{avg_deco .:.2} ms", time: {dompressionrage decfo("  Aveintd.log.  s});
      ess_timempr_co ms", .{avgme: {d:.2}ression tige compAveraog.info("  std.l
  .len));
  tems(test_data.ifloatFromInt/ @as(f64, @ize)) mpressed_s(avg_coatFromIntas(f64, @flo = @io_rat compressiononst   c    ;
 tionssize / iteracompressed_ize = total_sed_smpresavg_cost     con  0; // ms
  / 1_000_000.ns)) (iteratioIntoatFrom4, @fl @as(f6)) /metimpress_l_decot(totatFromIn@floaf64, me = @as(ompress_tiecg_d const av  / ms
     00.0; /_0000ns)) / 1_tioromInt(iteraatF@flo @as(f64, time)) /ss_al_compremInt(totatFroas(f64, @flos_time = @mpresonst avg_co  c


        }d);sseee(decompre.frator     alloc
       );(compressedfreecator.        allo
              ed);
  ssres, decompt_data.item, teses(u8EqualSlicexpecttesting.        try ess
    y correctn Verif     //
        );
      tartompress_snd - dececompress_e(d+= @intCasttime ecompress_   total_d
      );
Timestamp(time.nano std.nd =_e decompress const     n);
      ta.items.leed, test_dacompress backend, s(allocator,ecompreskends.dressionBac= try Compd mpressedecoonst           cstamp();
  imeime.nanoTrt = std.tcompress_sta  const de          time
 ssiondecompre/ Measure           /
       ;
       ssed.len += compresizeressed_al_comptot   ;
         _start)compressess_end - mprtCast(co @inss_time +=rel_compota  t

    p();oTimestamtd.time.nan s =mpress_endcoonst           cvel());
  sionLeetCompresd.gtems, backendata.i test_backend,r, toress(allocackends.compompressionBad = try Cressest comp   con;
         amp()nanoTimest= std.time.ess_start onst compr        c   time
  essionsure compr// Mea           ns) |_| {
 atio(0..iter for
               0;
size = sed_size: uotal_compresr t     va= 0;
   ime: u64 ss_t_decomprear total  v
      : u64 = 0;press_time total_comar        v0;
 = 10 iterationsst
        con      );
  nd)}backeme({@tagNa {s}", .kend:bacest for nce tformaerg.info("P     std.lo

 ontinue;le()) cAvailabis (!backend.   ifd| {
     ds) |backenr (backen
    fo };
, .customneBackend{ .nopressionsion.ComCompresatchTable= [_]Disps  backendston
    c
   ;
    }type_id))Bytes(&e(std.mem.asdSlic_data.appentest   try  IDs
     erent type // 10 diff% 10) + 1);@intCast((i 2 = : u3st type_id
        conKBs = 10 byte2560 * 4 { // ..2560) |i|(0
    for ternsic patth realistwiest data  of terate 10KB
    // Gen;
    einit()a.datefer test_dor);
    dit(allocatinayList(u8).= std.Arr test_data ce
    varerformane pasurta to mearge test da Create l //

   g.allocator;stinocator = teconst alln" {
    egressiormance rerfo pioncompress"

test }
}    }
    OK");
    rrectness: o("    Co.infog      std.l;
      essed)omprdata, dect_case.8, teses(uictEqualSlexpecg. testin   try         ess
ctn corre // Verify
             pressed);
.free(decomr allocator        defe };

     n err;  retur
     {err});}", .failed: {n pressio"    Decomr(.log.er         std
 err| { |len) catch_case.data.essed, testcomprkend, actor, ballocaress(ends.decompBackpression = Compressedt decomcons
    ioncompresst de     // Tes
              ;
   .len })pressed comdata.len,{ test_case. .} bytes",} -> {mpressed: { Co   .log.info("       std
              sed);
   compresocator.free(  defer all            };

      continue;             r});
er{}", .{failed: ompression    C" g.warn(      std.lo     {
      h |err|atc cel())ionLevCompressend.getata, back_case.dd, testenackor, bcatmpress(allo.coBackendsssionsed = Compreonst compres           con
 pressi com // Test

 (backend)});Nametags}", .{@Backend: {("  .infod.log          st
           inue;
()) contailablend.isAv (!backe    if
        |backend| {(backends)      for
   ;
  en }).data.lst_case, tenametest_case., .{ "({} bytes) case: {s} g edge"Testing.info(    std.lo   _case| {
 |testes) t_cas   for (tes
    ustom };
.none, .conBackend{ mpressision.CobleCompresDispatchTands = [_]ckebaonst
    c  };
    25 },
   ** xDE, 0xF0 } 00x9A, 0xBC,x78,  0x56, 0x34, 02, 0x1ta = &[_]u8{data", .darandom  "name =.{ .},
        ** 50) 5 } x5 0_]u8{ 0xAA,ata = &([ttern", .dg paternatin = "al .name
        .{ ** 100) },[_]u8{0xFF}data = &( ones", .= "allme      .{ .na},
   0} ** 100)  = &([_]u8{.dataos", "all zer { .name =  . },
      [_]u8{0x42}a = &.datle byte", "sing .name =        .{u8{} },
 &[_]a = data", .dat"empty name = { .
        .   }{t u8,
 ]consata: [  d,
      u8nst  []come:   na     {
 = [_]structtest_cases  const   ge cases
  // Test ed
  ocator;
 llting.aator = tes alloc  const {
   cases"th edgectness wi correionpressom"cest
t   }
}
n()});
 .getWritte{fbs\n{s}", .report:Compression ("td.log.info    s    ());
terbs.wriort(fonReppressiomn.generateCpressio    try com;
    m(&buffer)dBufferStrea.fixestd.io var fbs =   ed;
     8 = undefin96]u [40er:buffr       va  report
n essiocompr/ Generate         /
0});
  vement * 10ance_improotal_performary.tization_summ .{optim",2}%: {d:.matetiement ese improverformancnfo("  P.ilog     std.ved});
   l_memory_say.totaartion_summzaimi.{opts", ed: {} bytel memory sav("  Totafolog.in  std.   );
   d}es_eliminateal_entriummary.totation_s", .{optimizd: {}eliminates  entrieo("  Total.log.inf  std     ;
 ms.len}).ites_appliedary.passesummation_iz, .{optim": {}ses appliedion pasptimizatnfo("  Og.i    std.lo

 ();initmmary.demization_su opti  defer      ble);
Table(&ta.optimizeon compressi= tryion_summary timizatvar op       tion
 optimizaest  T  //

            }  que)});
gName(techni.{@ta- {s}", o("    .infog       std.l{
     | nique) |tech.itemses_appliedniquresult.techpression_com ( for
 s.len});
  lied.itemiques_applt.technion_resu.{compresslied: {}", appes quo("  Technig.inflo     std.o});
   n_ratimpressio_result.cocompression", .{io: {d:.3}ratCompression "  og.info( std.l    });
   zeed_siompresst.con_resulressiompytes", .{c: {} bsized essepr"  Cominfo(td.log. s
 nal_size});ult.origission_resmpre", .{coes: {} bytsizeinal ig  Or.log.info("td    s
init();
desion_result.r compres      defele);
  abTable(&ton.compresscompressiesult = try ession_r   var compron
     ompressi  // Test c
  ;
        ion(&impl2)ementatble.addImpl     try tapl1);
   (&imentationImplemdd try table.a
   ;
         }
 = 200,rankspecificity_   .
         ummy(),an.dourceSpatchTable.SDispedmiztion = Optiocaource_l  .s         t.PURE),
 fectSeatchTable.EfDispit(OptimizedectSet.inhTable.EffspatcOptimizedDi.effects =             ,
pe= string_tyurn_type_id    .ret      ype},
   ircle_teId{cegistry.Typ&[_]TypeR_type_ids = aram        .p    },
 , .id = 2 "test"dule =", .mo"testname = nctionId{ .hTable.FumizedDispatcd = Optition_i   .func       ation{
  ImplementchTable.atptimizedDispmpl2 = O i const
                };
    k = 100,
 anficity_rspeci           .
 dummy(),rceSpan.oupatchTable.SmizedDis = Optiocationurce_l .so         ),
  tSet.PUREle.EffecTabatchmizedDisp(Opti.initectSetTable.EffizedDispatchts = Optimfec  .ef         ,
 ng_typeriype_id = st .return_t        ,
   t_type}peId{in.TyypeRegistry[_]Type_ids = &    .param_t
        ,id = 1 }est", ."tdule = "test", .mo= ame Id{ .nnctionle.FuatchTabptimizedDisp Otion_id =     .func
  mentation{lechTable.ImpimizedDispatl1 = Opt   const imps
     tationplemenome test im// Add s
              ;
it()inble.dedefer ta
        e});d{int_typgistry.TypeI_]TypeRe", &[test_func, "locator(alnitble.iispatchTazedDry Optimi= tle     var tab
    able tdispatch mock eate a      // Cr
  nit();
  eision.dompresefer c   d);
     figtry, conpe_regis&ty, ocatorg(allWithConfinitession.ihTableCompratcsion = Dispvar compres
     ;
        ", .{i}){}ation on configurompressi"Testing clog.info(     std.
   onfig, i| {..) |c, 0onfigs
    for (c    };
  },
    ns
      zatiomioptiensive kip expe, // S falsrdering =cy_reoble_frequen       .ena= 1,
     n_level  .compressio           lz4,
= .backend       .
 sionConfig{Compresression.chTableCompispatn
        Donfiguratioed-focused cpe     // S    },
       savings
 % minimum0.01, // 1shold = n_threcompressio         .  n = 100,
 r_compressioize_fo    .min_s
    level = 9,ompression_       .ctom,
     nd = .cuscke       .ba     nConfig{
Compression.essioableComprspatchT     Di  ion
 pressive com // Aggress  ,
     Config{}mpressionion.CoCompressblechTa    Dispattion
    guraconfi// Default      ig{
   ressionConfssion.CompomprechTableC_]Dispatnfigs = [   const coions
 iguratnt confth differe wission systemrecompate // Cre
  ype});
    _thapeId{stry.Type[_]TypeRegisle_sealed, &, .tabcle"ire("C.registerTypgistryype_rery t = t circle_type   const{});
 le_open, &.", .tab"ShapesterType(gistry.regiy type_re_type = trapeconst sh);
    {}mitive, &.", .pritringe("syp.registerT_registrye = try typestring_typ const .{});
   , & .primitivet",pe("inrTyegistetry.ry type_regis_type = tronst int
    cest typeser some t// Regist
    );
    it(try.deinregisdefer type_tor);
    .init(allocaistryTypeRegtry try = type_regis  var egistry
   type rck a mo   // Create;

 .allocatorestingtor = tcaonst allo {
    ction"on integrapressitable com "dispatch }

test
    }
ritten()});{fbs.getW, .:\n{s}"hmark reportenc"Bfo(  std.log.in;
      .writer())tReport(fbssult.prinbenchmark_rery     tffer);
    &butream(BufferSstd.io.fixed fbs =        varefined;
 096]u8 = undbuffer: [4       var results
 detailed   // Print
    e});
   _scorbestesult.{benchmark_r {d:.3}", .ore:t sceslog.info("Bstd.      end)});
  ended_backommk_result.rece(benchmar.{@tagNam", ckend: {s}ed baommend("Recog.infotd.l        s

cator);allonit(eisult.denchmark_refer b    de   ght);
 ems, weita.itest_dallocator, t(aalBackendimptectOnchmark.selressionBempt = try Cork_resulhma  var benc

ht});.{weig", d:.1}weight: {erformance rking with pmao("Benchg.infstd.lo    ht| {
    s) |weigightor (we  fd

  -focuseced, speedlan ban-focused,essiompr // Co }; 0.5, 1.0[_]f64{ 0.0,ights = onst wehts
    cweigance rent performst diffe   // Te


    } }
        % 256));st(i@intCaappend(a.st_dat try te
       dom datame ransod  Ad   //     else {
           } tern);
 Slice(&pat_data.appendtry test         0x04 };
   x02, 0x03,  0x01, 0u8{n = [_]atter    const p        < 5) {
 (i % 10      if    patterns
edatd some repe// Ad       |i| {
 0..1000)    for (terns
 patwith mixed  table chdispatte la // Simu
   nit();
   .deir test_data
    defeor);init(allocatu8).List(ay.Arrta = stdr test_da
    vaataest dstic treate reali
    // Cor;
   ting.allocatocator = test all   conson" {
 selectind  backendmark asion benchest "compr }
}

tesed);
   mpressdecoems, data.itt_ices(u8, tespectEqualSlesting.ex   try t
           d);
  sseecompreator.free(dfer alloc     det);
   esulator, &rllocessTable(acomprssion.debridCompre Hytry= essed nst decompr        compression
eco// Test d
;
  )})gs(ssionSavinCompreult.get, .{reses"yt{} bsaved: e o("  Spacnfstd.log.i
        tio});ssion_rault.compre.3}", .{restio: {d:pression rafo("  Comlog.in std.;
       size})compressed_al_result.finytes", .{ed: {} bcompressnal "  Fi.log.info(      stdze});
  mpressed_sic_cosemantit.", .{resul bytesmpressed: {}c co Semantiog.info(" td.l  s      ;
inal_size})ult.orig", .{resbytesal: {} in("  Orignfo.log.i    std
    );
       torocainit(allult.der resdefe;
        s, config)a.itemr, test_datlocatoessTable(alpression.comidComprt = try Hybr  var resul

  });
       first,ig.semantic_      confd),
      g.backename(confi @tagN
     i,       .{
     rst={}", tic_fisemanend={s}, backuration {}: sting configfo("Te.log.in    std {
    |config, i|) ..nfigs, 0co
    for (  ;
    },
    }      savings
 minimum 5, // 5%old = 0.0on_threshcompressi          . true,
  tic_first = .seman        m,
   = .custo  .backend
          g{ionConfipresson.CompressiTableComDispatch
      tic + customeman: s/ Hybrid     /},
         = false,
  c_first nti .sema           om,
.custnd =      .backe
       nfig{ssionCoComprempression.ableCo   DispatchT only
     pressionom comCust       //      },
 e,
    tru_first =   .semantic      none,
   end = .     .back
       fig{nConCompressioompression.tchTableC     Dispa
   antic only   // Sem
   sionConfig{resompn.CleCompressiohTab[_]Dispatcfigs =  const contions
   rant configuh differeession witpr comybrid/ Test h

    / }256));
   t(i % tCasa.append(@intry test_dat         |i| {
..100) for (0
   aue datiqe und som/ Ad  /
  }
    ;
    e(&pattern)endSlic.appry test_data t| {
       ..20) |_or (0peIds
    f// Two Ty0 }; 0, 0x00, 0x00x02, 0x0x00, , 0x00, 01, 0x00_]u8{ 0x0 pattern = [)
    constrnsn type patteg commoatinterns (simuld patd repeateAd    // ;

ta.deinit()_dar test   defe
 cator);).init(alloyList(u8= std.Arrata var test_daries
    table entdispatch  simulating atatest d Create
    //llocator;
 = testing.aallocator
    const ession" {eneral comprnd gemantic asion with sd compres"hybri}

test essed);
decomprta.items, _da testlSlices(u8,Equactexpeg.stin    try te);

ompresseddecator.free(er allocdef;
    tems.len)est_data.iompressed, tm, cstoator, .cumpress(allocackends.decoompressionBtry Ced = ressmpconst decoion
    ecompress Test d
    //
    });* 100.0,
  tems.len)) st_data.iromInt(te@floatF, @as(f64n)) / pressed.leInt(comfloatFrom @   @as(f64,
     sed.len,res  compn,
      ata.items.le     test_d
   , .{)".2}% ratios ({d: byten: {} -> {}ssiotom compreinfo("Cus std.log.
 );lendata.items..len < test_sedes(comprsting.expect    try te;

mpressed)free(cor allocator.   defe5);
 , ta.itemstom, test_da .cusator,(allocnds.compressssionBackepreomd = try Cst compresseon
    cont compressi   // Tes }

 ;
   d))pe_ies(&tymem.asBytce(std.Slipendst_data.ap      try tee_id| {
  ) |typr (type_ids fo 5 };
   4,, 5, 4, 5, 3, 42,  3, 1, , 3, 1, 2,2{ 1, 2= [_]u3ids onst type_ns
    cve patteritith repet each) wibytes IDs (4 pemulate ty   // Si

 init();data.der test_
    defellocator);t(a.iniist(u8)ayLstd.Arrta = var test_da   es
 ch tablatdispypical of terns tth pata wite test dat
    // Crea
   or;ng.allocatator = testiconst alloc   hm" {
 algoritcompression om ustt "c}

tes }
    }
;
       available)ng.expect(   try testi      {
    .custom) nd ==cke ba= .none orckend =    if (bailable
    va be aysshould alwand custom  None a //

       level });ilable, ), avaame(backendtagN={}", .{ @}, levelavailable={ {s}: "Backendtd.log.info(       s

        nLevel();siod.getCompresel = backenconst lev      ();
  ble.isAvailae = backendablvail  const a
       { |backend|ackends)  for (b
  };
   td, .custom z4, .zsd{ .none, .lionBackenmpresspression.CohTableCom_]Dispatckends = [onst bac {
    cbility"nds availabackecompression  "

testle;abpatchTismizedDOptizig").tch_tables._dispazed../optimirt("e = @impopatchTablizedDisst Optimonry;
c).TypeRegistg"stry.zi/type_regi@import("..istry = Regonst Type

cnBenchmark;).Compressio"zigion.esspr_com_table../dispatch"rt(k = @impoonBenchmarressimp;
const CosionompresbridCn.zig").Hycompressiopatch_table_/disrt("..mposion = @iidCompresnst Hybrds;
cosionBacken.Compression.zig")compresh_table_patcdisort("../impackends = @essionBst Compression;
conTableCompr.Dispatch")igpression.zomtable_ctch_ispat("../d@impor= ression TableComppatcht Disons

cor;ocat std.mem.Allator =
const Alloc.testing;ting = stdst testd");
con"sd = @import(const st
