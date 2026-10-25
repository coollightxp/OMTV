/// 电视猫 EPG 频道映射（央视频 pid -> 电视猫节目页路径）。
///
/// 电视猫节目页形如 `/program/<GROUP>-<SLUG>-w<N>.html`，
/// 其中 N 为本周星期几（1 = 周一 … 7 = 周日），路径前缀保存在此表。
///
/// 未收录的频道（CCTV-5+、CCTV-8K、数字付费频道）由央视频 EPG 兜底。
/// 注意：电视猫内部编号与频道号并不一致（例如 CCTV-14少儿 对应
/// `CCTV-CCTV15`、CCTV-16奥林匹克 对应 `CCTV-CCTVOLY`），
/// 表内已逐条按页面标题核对，请勿按频道号自行推算。
class TvmaoChannels {
  const TvmaoChannels._();

  static const Map<String, String> paths = {
    // ==================== 央视频道 ====================
    '600001859': 'CCTV-CCTV1',
    '600001800': 'CCTV-CCTV2',
    '600001801': 'CCTV-CCTV3',
    '600001814': 'CCTV-CCTV4',
    '600001818': 'CCTV-CCTV5',
    '600108442': 'CCTV-CCTV6',
    '600004092': 'CCTV-CCTV7',
    '600001803': 'CCTV-CCTV8',
    '600004078': 'CCTV-CCTV9',
    '600001805': 'CCTV-CCTV10',
    '600001806': 'CCTV-CCTV11',
    '600001807': 'CCTV-CCTV12',
    '600001811': 'CCTV-CCTV13',
    '600001809': 'CCTV-CCTV15', // CCTV-14 少儿
    '600001815': 'CCTV-CCTV16', // CCTV-15 音乐
    '600098637': 'CCTV-CCTVOLY', // CCTV-16 奥林匹克
    '600001810': 'CCTV-CCTV17NY', // CCTV-17 农业农村
    '600002264': 'CCTV-CCTV4K',
    '600014550': 'CCTV-CCTV19', // CGTN
    '600084781': 'CCTV-CCTV18', // CGTN 纪录
    '600084744': 'CCTV-CCTV17', // CGTN 西班牙语
    '600084704': 'CCTV-CCTVF', // CGTN 法语
    '600084782': 'CCTV-CCTVA', // CGTN 阿拉伯语
    '600084758': 'CCTV-CCTVR', // CGTN 俄语

    // ==================== 卫视频道 ====================
    '600002309': 'BTV-BTV1',
    '600152137': 'TJTV-TJTV1',
    '600002493': 'HEBEI-HEBEI1',
    '600190407': 'SXTV-SXTV1',
    '600190401': 'NMGTV-NMGTV1',
    '600002505': 'LNTV-LNTV1',
    '600190405': 'JILIN-JILIN1',
    '600002498': 'HLJTV-HLJTV1',
    '600002483': 'DONGFANG-DONGFANG1',
    '600002521': 'JSTV-JSTV1',
    '600002520': 'ZJTV-ZJTV1',
    '600002532': 'AHTV-AHTV1',
    '600002484': 'FJTV-FJTV2',
    '600002503': 'JXTV-JXTV1',
    '600002513': 'SDTV-SDTV1',
    '600002525': 'HNTV-HNTV1',
    '600002508': 'HUBEI-HUBEI1',
    '600002475': 'HUNANTV-HUNANTV1',
    '600002485': 'GDTV-GDTV1',
    '600002481': 'SZTV-SZTV1',
    '600002509': 'GUANXI-GUANXI1',
    '600002506': 'HAINANTV-HAINANTV1', // 海南自贸频道（现海南卫视）
    '600002531': 'CCQTV-CCQTV1',
    '600002516': 'SCTV-SCTV1',
    '600002490': 'GUIZOUTV-GUIZOUTV1',
    '600190402': 'YNTV-YNTV1',
    '600190403': 'XIZANGTV-XIZANGTV2', // 西藏卫视（汉语）
    '600190400': 'SHXITV-SHXITV1',
    '600190408': 'GSTV-GSTV1',
    '600190406': 'QHTV-QHTV1',
    '600190737': 'NXTV-NXTV2',
  };

  static String? pathFor(String pid) => paths[pid];
}
