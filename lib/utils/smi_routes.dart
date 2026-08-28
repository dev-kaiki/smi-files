// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/utils/smi_routes.dart

class SmiRoutes {
  // =========================
  // AUTH / HOME
  // =========================
  static const login = '/login';
  static const home = '/home';

  // =========================
  // OS FOLDERS (os_folders) - app de mídias
  // =========================
  static const osFolders = '/os'; // lista de pastas
  static const newOsFolder = '/os/new';

  /// Página de mídias da OS (use query param ou helper abaixo)
  /// Ex.: /os/media?osFolderId=123
  static const osMedia = '/os/media';

  static String osMediaWithId(String osFolderId) =>
      '$osMedia?osFolderId=$osFolderId';

  // =========================
  // OS (tabela "os") - OsListPage / OsDetailPage
  // =========================
  static const osDb = '/os-db';
  static String osDbDetail(String osId) => '$osDb/$osId';

  // =========================
  // OS (Servidor) - OsServerListPage / OsServerDetailPage
  // =========================
  static const osServer = '/os-server';
  static String osServerDetail(String osId) => '$osServer/$osId';

  // =========================
  // PREVIEW DE VÍDEO (Signed URL)
  // =========================
  static const videoPreview = '/video';

  /// Ex.: /video?path=clientes%2Fabc%2Fvideo.mp4
  static String videoPreviewWithPath(String storagePath) =>
      '$videoPreview?path=${Uri.encodeComponent(storagePath)}';
}
