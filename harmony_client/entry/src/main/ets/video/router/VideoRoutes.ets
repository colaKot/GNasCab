/**
 * 影音管理模块共享路由参数类（各页面 import 使用，避免循环依赖）。
 * 路由名常量统一在 AppRouter 中定义（VIDEO_* 前缀）。
 */

/** 视频详情页参数 */
export class VideoDetailPageParam {
  indexId: number = 0;
}

/** 视频列表页参数（对齐 Flutter AppVideoListPage 构造参数） */
export class VideoListPageParam {
  title: string = '';
  /** 初始媒体类型：movie/tv/image/'' */
  initialMediaType: string = '';
  /** 列表类型：''/history/favorite 等 */
  listType: string = '';
  albumId: number = 0;
  collectionId: number = 0;
  smartAlbumId: number = 0;
  initialGenres: string[] = [];
  initialRegions: string[] = [];
  initialActors: string[] = [];
  initialDirectors: string[] = [];
  /** 所属影视库 id（>0 时按库过滤） */
  libraryId: number = 0;
}

/** 影视库媒体浏览页参数（图片/混合库：网格 + 竖向全屏浏览） */
export class VideoMediaBrowserPageParam {
  libraryId: number = 0;
  /** 影视库类型：movie/tv/image/mixed */
  libType: string = 'image';
  title: string = '';
}

/** 相册视频列表页参数（对齐 Flutter AppVideoAlbumVideosPage） */
export class VideoAlbumVideosPageParam {
  albumId: number = 0;
  smartAlbumId: number = 0;
  collectionId: number = 0;
  title: string = '';
}

/** 自建相册列表页参数（对齐 Flutter AppVideoAlbumListPage） */
export class VideoAlbumListPageParam {
  /** 进入后自动打开编辑弹窗的相册 id（0 不打开） */
  initialEditId: number = 0;
  autoOpenCreate: boolean = false;
}

/** 智能相册列表页参数（对齐 Flutter AppVideoSmartAlbumListPage） */
export class VideoSmartAlbumListPageParam {
  initialEditId: number = 0;
  autoOpenCreate: boolean = false;
}

/** 照片合集列表页参数（对齐 Flutter AppVideoCollectionListPage） */
export class VideoCollectionListPageParam {
  initialEditId: number = 0;
  autoOpenCreate: boolean = false;
}
