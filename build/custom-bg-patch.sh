#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 洛雪音乐 移动版（lx-music-mobile v1.9.2）——「自定义背景 + 自定义主题」补丁
#
# 用法：把本脚本放到仓库根目录的 build/ 下，然后在源码根目录执行
#     bash build/custom-bg-patch.sh [源码目录]      # 默认 lx
#
# 功能：
#   * 设置 → 基础设置 → 自定义背景：选图、蒙版透明度、蒙版颜色、填充方式、背景模糊
#   * 设置 → 基础设置 → 主题网格末尾「+ 添加主题」：自定义主题名称、主题色、
#     字体颜色、内容区域背景色、暗色主题；保存后在网格里显示，点击即切换；
#     长按自定义主题可删除
#   * 包名改为 cn.toside.music.mobile.custombg（可与官方版、其他魔改版共存）
#   * 应用名改为「洛雪·自定义背景」
#
# 本脚本可重复执行，已应用的改动会自动跳过。
# ---------------------------------------------------------------------------
set -euo pipefail

TARGET="${1:-lx}"
cd "$TARGET"

if [ ! -f package.json ] || ! grep -q '"name": "lx-music-mobile"' package.json; then
  echo "!! 当前目录不是 lx-music-mobile 源码根目录: $(pwd)" >&2
  exit 1
fi

echo "==> 目标源码: $(pwd)"

# 1. 自定义背景设置项
mkdir -p src/screens/Home/Views/Setting/settings/Theme
cat > src/screens/Home/Views/Setting/settings/Theme/CustomBg.tsx <<'FILE_EOF'
import { memo, useCallback, useMemo, useRef, useState } from 'react'
import { TouchableOpacity, View } from 'react-native'
import RNFS from 'react-native-fs'

import SubTitle from '../../components/SubTitle'
import Slider, { type SliderProps } from '../../components/Slider'
import Text from '@/components/common/Text'
import Image from '@/components/common/Image'
import CheckBox from '@/components/common/CheckBox'
import FileSelect, { type FileSelectType } from '@/components/common/FileSelect'
import { useI18n } from '@/lang'
import { useSettingValue } from '@/store/setting/hook'
import { useTheme } from '@/store/theme/hook'
import { updateSetting } from '@/core/common'
import { createStyle, toast } from '@/utils/tools'
import { extname, privateStorageDirectoryPath } from '@/utils/fs'

type ResizeMode = LX.AppSetting['theme.customBg.resizeMode']

const RESIZE_MODES: ResizeMode[] = ['cover', 'contain', 'stretch']
const MASK_COLORS = ['rgba(0, 0, 0, 1)', 'rgba(255, 255, 255, 1)'] as const
const BLUR_RADIUS = 25
const CUSTOM_BG_DIR = privateStorageDirectoryPath + '/custom_bg'

// 选好的图片会被复制到应用私有目录，避免原图被移动/删除后背景失效
const saveCustomBg = async(from: string, prevPath?: string) => {
  const dir = CUSTOM_BG_DIR
  const ext = extname(from) || 'jpg'
  // 文件名带时间戳：路径每次都变，图片才能立即刷新（否则会命中 Image 缓存，要重启才生效）
  const to = dir + '/bg_' + Date.now() + '.' + ext
  try {
    if (!await RNFS.exists(dir)) await RNFS.mkdir(dir)
    await RNFS.copyFile(from, to)
    updateSetting({ 'theme.customBg.path': to })
    if (prevPath && prevPath != to && prevPath.startsWith(dir + '/')) {
      try {
        if (await RNFS.exists(prevPath)) await RNFS.unlink(prevPath)
      } catch {
        // 清理旧图失败不影响使用
      }
    }
  } catch (err: any) {
    // 复制失败时退回直接使用原路径
    console.log('save custom bg failed: ' + (err?.message ?? String(err)))
    updateSetting({ 'theme.customBg.path': from })
  }
}

const Item = ({ check, label, onPress, need = true }: {
  check: boolean
  label: string
  onPress: () => void
  need?: boolean
}) => {
  return <CheckBox marginBottom={3} check={check} label={label} onChange={onPress} need={need} />
}

export default memo(() => {
  const t = useI18n()
  const theme = useTheme()
  const path = useSettingValue('theme.customBg.path')
  const maskAlpha = useSettingValue('theme.customBg.maskAlpha')
  const maskColor = useSettingValue('theme.customBg.maskColor')
  const blur = useSettingValue('theme.customBg.blur')
  const resizeMode = useSettingValue('theme.customBg.resizeMode')
  const fileSelectRef = useRef<FileSelectType>(null)
  const [sliderAlpha, setSliderAlpha] = useState(maskAlpha)
  const [isSliding, setSliding] = useState(false)

  const handleSelectClick = useCallback(() => {
    fileSelectRef.current?.show({
      title: t('setting_custom_bg_select'),
      dirOnly: false,
      filter: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
    }, (selectedPath) => {
      void saveCustomBg(selectedPath, path).then(() => {
        toast(t('setting_custom_bg_applied'))
      })
    })
  }, [t, path])

  const handleClear = useCallback(() => {
    updateSetting({ 'theme.customBg.path': '' })
    toast(t('setting_custom_bg_cleared'))
  }, [t])

  const handleSlidingStart = useCallback<NonNullable<SliderProps['onSlidingStart']>>(() => {
    setSliding(true)
  }, [])
  const handleValueChange = useCallback<NonNullable<SliderProps['onValueChange']>>(value => {
    setSliderAlpha(Math.round(value))
  }, [])
  const handleSlidingComplete = useCallback<NonNullable<SliderProps['onSlidingComplete']>>(value => {
    setSliding(false)
    const next = Math.round(value)
    if (next == maskAlpha) return
    updateSetting({ 'theme.customBg.maskAlpha': next })
  }, [maskAlpha])

  const setMaskColor = useCallback((color: string) => {
    updateSetting({ 'theme.customBg.maskColor': color })
  }, [])
  const setBlur = useCallback((isBlur: boolean) => {
    updateSetting({ 'theme.customBg.blur': isBlur ? BLUR_RADIUS : 0 })
  }, [])
  const setResizeMode = useCallback((mode: ResizeMode) => {
    updateSetting({ 'theme.customBg.resizeMode': mode })
  }, [])

  const maskColorList = useMemo(() => ([
    { color: MASK_COLORS[0], label: t('setting_custom_bg_mask_color_black') },
    { color: MASK_COLORS[1], label: t('setting_custom_bg_mask_color_white') },
  ]), [t])

  const resizeModeList = useMemo(() => RESIZE_MODES.map(mode => ({
    mode,
    label: t(`setting_custom_bg_resize_${mode}` as any),
  })), [t])

  return (
    <SubTitle title={t('setting_custom_bg')}>
      <View style={styles.content}>
        <View style={styles.row}>
          {
            path
              ? <Image url={path} cache={false} style={{ ...styles.preview, borderColor: theme['c-border-background'] }} />
              : <View style={{ ...styles.previewEmpty, backgroundColor: theme['c-primary-background'], borderColor: theme['c-border-background'] }} />
          }
          <View style={styles.btns}>
            <TouchableOpacity style={{ ...styles.btn, backgroundColor: theme['c-button-background'] }} onPress={handleSelectClick}>
              <Text size={13} color={theme['c-button-font']}>{t(path ? 'setting_custom_bg_change' : 'setting_custom_bg_select')}</Text>
            </TouchableOpacity>
            {
              path
                ? <TouchableOpacity style={{ ...styles.btn, backgroundColor: theme['c-button-background'] }} onPress={handleClear}>
                    <Text size={13} color={theme['c-button-font']}>{t('setting_custom_bg_clear')}</Text>
                  </TouchableOpacity>
                : null
            }
          </View>
        </View>
        <Text size={12} color={theme['c-font-label']} style={styles.tip}>
          {path ? t('setting_custom_bg_tip_on') : t('setting_custom_bg_tip_off')}
        </Text>
      </View>

      <View style={styles.sliderRow}>
        <Text size={13} color={theme['c-primary-font']}>{t('setting_custom_bg_mask_alpha')}: {isSliding ? sliderAlpha : maskAlpha}%</Text>
        <Slider
          minimumValue={0}
          maximumValue={100}
          onSlidingComplete={handleSlidingComplete}
          onValueChange={handleValueChange}
          onSlidingStart={handleSlidingStart}
          step={5}
          value={maskAlpha}
        />
      </View>

      <View style={styles.checkboxList}>
        <Text size={13} color={theme['c-primary-font']} style={styles.groupLabel}>{t('setting_custom_bg_mask_color')}</Text>
        <View style={styles.inlineCheckbox}>
          {
            maskColorList.map(({ color, label }) => (
              <View key={color} style={styles.inlineItem}>
                <Item check={maskColor == color} label={label} onPress={() => { setMaskColor(color) }} />
              </View>
            ))
          }
        </View>
      </View>

      <View style={styles.checkboxList}>
        <Text size={13} color={theme['c-primary-font']} style={styles.groupLabel}>{t('setting_custom_bg_resize')}</Text>
        <View style={styles.inlineCheckbox}>
          {
            resizeModeList.map(({ mode, label }) => (
              <View key={mode} style={styles.inlineItem}>
                <Item check={resizeMode == mode} label={label} onPress={() => { setResizeMode(mode) }} />
              </View>
            ))
          }
        </View>
      </View>

      <View style={styles.checkboxList}>
        <Item check={blur > 0} label={t('setting_custom_bg_blur')} onPress={() => { setBlur(blur == 0) }} need={false} />
      </View>

      <FileSelect ref={fileSelectRef} />
    </SubTitle>
  )
})

const styles = createStyle({
  content: {},
  row: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  preview: {
    width: 64,
    height: 38,
    borderRadius: 4,
    borderWidth: 1,
  },
  previewEmpty: {
    width: 64,
    height: 38,
    borderRadius: 4,
    borderWidth: 1,
  },
  btns: {
    flexDirection: 'row',
    gap: 10,
    marginLeft: 15,
  },
  btn: {
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 4,
  },
  tip: {
    marginTop: 6,
  },
  sliderRow: {
    marginTop: 12,
  },
  checkboxList: {
    marginTop: 10,
  },
  groupLabel: {
    marginBottom: 6,
  },
  inlineCheckbox: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  inlineItem: {
    marginRight: 20,
  },
})
FILE_EOF

# 2. 主界面背景渲染
cat > src/components/PageContent.tsx <<'FILE_EOF'
// import { useEffect, useState } from 'react'
import { View } from 'react-native'
import { useTheme } from '@/store/theme/hook'
import ImageBackground from '@/components/common/ImageBackground'
import { useWindowSize } from '@/utils/hooks'
import { useMemo } from 'react'
import { scaleSizeAbsHR } from '@/utils/pixelRatio'
import { defaultHeaders } from './common/Image'
import SizeView from './SizeView'
import { useBgPic } from '@/store/common/hook'
import { useSettingValue } from '@/store/setting/hook'

interface Props {
  children: React.ReactNode
}

const BLUR_RADIUS = Math.max(scaleSizeAbsHR(18), 10)

const getImageUri = (path: string) => path.startsWith('/') ? 'file://' + path : path

export default ({ children }: Props) => {
  const theme = useTheme()
  const windowSize = useWindowSize()
  const pic = useBgPic()
  const customBgPath = useSettingValue('theme.customBg.path')
  const customBgMaskAlpha = useSettingValue('theme.customBg.maskAlpha')
  const customBgMaskColor = useSettingValue('theme.customBg.maskColor')
  const customBgBlur = useSettingValue('theme.customBg.blur')
  const customBgResizeMode = useSettingValue('theme.customBg.resizeMode')
  // const [wh, setWH] = useState<{ width: number | string, height: number | string }>({ width: '100%', height: Dimensions.get('screen').height })

  // 固定宽高度 防止弹窗键盘时大小改变导致背景被缩放
  // useEffect(() => {
  //   const onChange = () => {
  //     setWH({ width: '100%', height: '100%' })
  //   }
  //
  //   const changeEvent = Dimensions.addEventListener('change', onChange)
  //   return () => {
  //     changeEvent.remove()
  //   }
  // }, [])
  // const handleLayout = (e: LayoutChangeEvent) => {
  //   // console.log('handleLayout', e.nativeEvent)
  //   // console.log(Dimensions.get('screen'))
  // }
  // console.log('render page content')

  const themeComponent = useMemo(() => (
    <View style={{ flex: 1, overflow: 'hidden' }}>
      <ImageBackground
        style={{ position: 'absolute', left: 0, top: 0, height: windowSize.height, width: windowSize.width, backgroundColor: theme['c-content-background'] }}
        source={theme['bg-image']}
        resizeMode="cover"
      >
      </ImageBackground>
      <View style={{ flex: 1, flexDirection: 'column', backgroundColor: theme['c-main-background'] }}>
        {children}
      </View>
    </View>
  ), [children, theme, windowSize.height, windowSize.width])
  const customBgComponent = useMemo(() => {
    return (
      <View style={{ flex: 1, overflow: 'hidden' }}>
        <ImageBackground
          key={customBgPath}
          style={{ position: 'absolute', left: 0, top: 0, height: windowSize.height, width: windowSize.width, backgroundColor: customBgMaskColor }}
          source={{ uri: getImageUri(customBgPath) }}
          resizeMode={customBgResizeMode}
          blurRadius={customBgBlur}
        >
        </ImageBackground>
        {
          customBgMaskAlpha > 0
            ? <View style={{
                position: 'absolute',
                left: 0,
                top: 0,
                height: windowSize.height,
                width: windowSize.width,
                backgroundColor: customBgMaskColor,
                opacity: customBgMaskAlpha / 100,
              }}></View>
            : null
        }
        <View style={{ flex: 1, flexDirection: 'column' }}>
          {children}
        </View>
      </View>
    )
  }, [children, customBgPath, customBgMaskAlpha, customBgMaskColor, customBgBlur, customBgResizeMode, theme, windowSize.height, windowSize.width])
  const picComponent = useMemo(() => {
    return (
      <View style={{ flex: 1, overflow: 'hidden' }}>
        <ImageBackground
          style={{ position: 'absolute', left: 0, top: 0, height: windowSize.height, width: windowSize.width, backgroundColor: theme['c-content-background'] }}
          source={{ uri: pic!, headers: defaultHeaders }}
          resizeMode="cover"
          blurRadius={BLUR_RADIUS}
        >
          <View style={{ flex: 1, flexDirection: 'column', backgroundColor: theme['c-content-background'], opacity: 0.76 }}></View>
        </ImageBackground>
        <View style={{ flex: 1, flexDirection: 'column' }}>
          {children}
        </View>
      </View>
    )
  }, [children, pic, theme, windowSize.height, windowSize.width])

  return (
    <>
      <SizeView />
      {customBgPath ? customBgComponent : pic ? picComponent : themeComponent}
    </>
  )
}
FILE_EOF

# 3. 主题设置区注册
cat > src/screens/Home/Views/Setting/settings/Theme/index.tsx <<'FILE_EOF'
import { memo } from 'react'

// import Section from '../../components/Section'
import Theme from './Theme'
import IsAutoTheme from './IsAutoTheme'
import IsHideBgDark from './IsHideBgDark'
import IsDynamicBg from './IsDynamicBg'
import IsFontShadow from './IsFontShadow'
import CustomBg from './CustomBg'
// import { useI18n } from '@/lang/i18n'

export default memo(() => {
  return (
    <>
      <Theme />
      <CustomBg />
      <IsAutoTheme />
      <IsHideBgDark />
      <IsDynamicBg />
      <IsFontShadow />
    </>
  )
})
FILE_EOF

# 4. 主题网格（自定义主题入口 + 长按删除）
cat > src/screens/Home/Views/Setting/settings/Theme/Theme.tsx <<'FILE_EOF'
import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { View, TouchableOpacity, type ImageSourcePropType } from 'react-native'
import { setTheme } from '@/core/theme'
import { useI18n } from '@/lang'
import { useSettingValue } from '@/store/setting/hook'
import { useTheme } from '@/store/theme/hook'

import SubTitle from '../../components/SubTitle'
import { BG_IMAGES, getAllThemes, removeTheme, saveTheme, type LocalTheme } from '@/theme/themes'
import Text from '@/components/common/Text'
import { createStyle, confirmDialog, toast } from '@/utils/tools'
import { scaleSizeH } from '@/utils/pixelRatio'
import ThemeEditModal, { type ThemeEditModalType } from '@/components/ThemeEditModal'
import ImageBackground from '@/components/common/ImageBackground'
import themeState from '@/store/theme/state'

const useActive = (id: string) => {
  const activeThemeId = useSettingValue('theme.id')
  const isActive = useMemo(() => activeThemeId == id, [activeThemeId, id])
  return isActive
}

const ThemeItem = ({ id, name, color, showAll, image, onLongPress }: {
  id: string
  name: string
  color: string
  showAll: boolean
  image?: ImageSourcePropType
  onLongPress?: () => void
}) => {
  const theme = useTheme()
  const isActive = useActive(id)

  return (
    showAll || isActive ? (
      <TouchableOpacity style={{ ...styles.item, width: scaleSizeH(ITEM_HEIGHT) }} activeOpacity={0.5} onPress={() => { setTheme(id) }} onLongPress={onLongPress} delayLongPress={500}>
        <View style={{ ...styles.colorContent, width: scaleSizeH(COLOR_ITEM_HEIGHT), borderColor: isActive ? color : 'transparent' }}>
          {
            image
              ? <ImageBackground style={{ ...styles.imageContent, width: scaleSizeH(IMAGE_HEIGHT), backgroundColor: color }}
                  imageStyle={{ borderRadius: 4 }}
                  source={image} />
              : <View style={{ ...styles.imageContent, width: scaleSizeH(IMAGE_HEIGHT), backgroundColor: color }}></View>
          }
        </View>
        <Text style={styles.name} size={12} color={isActive ? color : theme['c-font']} numberOfLines={1}>{name}</Text>
      </TouchableOpacity>
    ) : null
  )
}

const MoreBtn = ({ showAll, setShowAll }: {
  showAll: boolean
  setShowAll: (showAll: boolean) => void
}) => {
  const theme = useTheme()
  const t = useI18n()

  return (
    showAll ? null
      : (
          <TouchableOpacity style={styles.moreBtn} activeOpacity={0.5} onPress={() => { setShowAll(!showAll) }}>
            <Text size={14} color={theme['c-primary-font']} numberOfLines={1}>{t('setting_basic_theme_more_btn_show')}</Text>
          </TouchableOpacity>
        )

  )
}

const AddItem = ({ onPress }: { onPress: () => void }) => {
  const theme = useTheme()
  const t = useI18n()
  return (
    <TouchableOpacity style={{ ...styles.item, width: scaleSizeH(ITEM_HEIGHT) }} activeOpacity={0.5} onPress={onPress}>
      <View style={{ ...styles.addBox, width: scaleSizeH(COLOR_ITEM_HEIGHT), borderColor: theme['c-border-background'] }}>
        <Text size={16} color={theme['c-primary-font']}>+</Text>
      </View>
      <Text style={styles.name} size={12} color={theme['c-font']} numberOfLines={1}>{t('setting_theme_add')}</Text>
    </TouchableOpacity>
  )
}

interface ThemeInfo {
  themes: Readonly<LocalTheme[]>
  userThemes: LX.Theme[]
  dataPath: string
}
const initInfo: ThemeInfo = { themes: [], userThemes: [], dataPath: '' }
export default memo(() => {
  const [showAll, setShowAll] = useState(false)
  const t = useI18n()
  const [themeInfo, setThemeInfo] = useState(initInfo)
  const editModalRef = useRef<ThemeEditModalType>(null)
  const setThemeId = useCallback((id: string) => {
    requestAnimationFrame(() => {
      setTheme(id)
    })
  }, [])

  const reloadThemes = useCallback(() => {
    void getAllThemes().then(info => {
      setThemeInfo({ ...info })
    })
  }, [])

  useEffect(() => {
    reloadThemes()
  }, [reloadThemes])

  const handleSaved = useCallback((theme: LX.Theme) => {
    void saveTheme(theme).then(reloadThemes).then(() => {
      setThemeId(theme.id)
      toast(t('theme_edit_saved'))
    })
  }, [reloadThemes, setThemeId, t])

  const handleDelete = useCallback((id: string, name: string) => {
    void confirmDialog({
      message: t('theme_delete_confirm', { name }),
      bgClose: false,
    }).then(confirm => {
      if (!confirm) return
      void removeTheme(id).then(() => {
        if (themeState.theme.id == id) setThemeId('green')
        reloadThemes()
        toast(t('theme_deleted'))
      })
    })
  }, [reloadThemes, setThemeId, t])

  return (
    <SubTitle title={t('setting_basic_theme')}>
      <View style={styles.list}>
        {
          themeInfo.themes.map(({ id, config }) => {
            return <ThemeItem
              key={id}
              color={config.themeColors['c-theme']}
              showAll={showAll}
              id={id}
              name={t(`theme_${id}` as any)}
              image={config.extInfo['bg-image'] ? BG_IMAGES[config.extInfo['bg-image'] as keyof typeof BG_IMAGES] : undefined}
              onLongPress={undefined} />
          })
        }
        {
          themeInfo.userThemes.map(({ id, name, config }) => {
            return <ThemeItem
              key={id}
              color={config.themeColors['c-theme']}
              showAll
              id={id}
              name={name}
              onLongPress={() => { handleDelete(id, name) }} />
          })
        }
        <AddItem onPress={() => { editModalRef.current?.show() }} />
        <MoreBtn showAll={showAll} setShowAll={setShowAll} />
      </View>
      <ThemeEditModal ref={editModalRef} onSaved={handleSaved} />
    </SubTitle>
  )
})

const ITEM_HEIGHT = 62
const COLOR_ITEM_HEIGHT = 36
const IMAGE_HEIGHT = 29
const styles = createStyle({
  list: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
    marginTop: 5,
  },
  item: {
    // marginRight: 15,
    alignItems: 'center',
    // marginTop: 5,
    // backgroundColor: 'rgba(0,0,0,0.2)',
  },
  colorContent: {
    height: COLOR_ITEM_HEIGHT,
    borderRadius: 4,
    borderWidth: 1.6,
    alignItems: 'center',
    justifyContent: 'center',
    // backgroundColor: 'rgba(0,0,0,0.2)',
  },
  imageContent: {
    height: IMAGE_HEIGHT,
    borderRadius: 4,
    // elevation: 1,
  },
  addBox: {
    height: COLOR_ITEM_HEIGHT,
    borderRadius: 4,
    borderWidth: 1,
    borderStyle: 'dashed',
    alignItems: 'center',
    justifyContent: 'center',
  },
  name: {
    marginTop: 2,
  },
  moreBtn: {
    marginLeft: 10,
    flexDirection: 'row',
    alignItems: 'center',
    // justifyContent: 'center',
    gap: 8,
  },
})
FILE_EOF

# 5. 自定义主题编辑弹窗
cat > src/components/ThemeEditModal.tsx <<'FILE_EOF'
import { forwardRef, memo, useCallback, useImperativeHandle, useRef, useState } from 'react'
import { ScrollView, TouchableOpacity, View } from 'react-native'

import Dialog, { type DialogType } from '@/components/common/Dialog'
import Text from '@/components/common/Text'
import Input from '@/components/common/Input'
import CheckBox from '@/components/common/CheckBox'
import { useTheme } from '@/store/theme/hook'
import { useI18n } from '@/lang'
import { createStyle, toast } from '@/utils/tools'
import { createCustomTheme } from '@/theme/themes/createCustomTheme'

export interface ThemeEditModalType {
  show: () => void
}

interface Props {
  onSaved: (theme: LX.Theme) => void
}

const PRIMARY_COLORS = [
  'rgb(77, 175, 124)',
  'rgb(52, 152, 219)',
  'rgb(77, 131, 175)',
  'rgb(243, 156, 18)',
  'rgb(211, 84, 0)',
  'rgb(231, 76, 60)',
  'rgb(244, 143, 177)',
  'rgb(142, 68, 173)',
  'rgb(108, 122, 137)',
  'rgb(47, 47, 47)',
  'rgb(0, 150, 136)',
  'rgb(149, 165, 166)',
] as const

const FONT_COLORS = [
  'rgb(33, 33, 33)',
  'rgb(0, 0, 0)',
  'rgb(96, 96, 96)',
  'rgb(229, 229, 229)',
  'rgb(255, 255, 255)',
] as const

const MAIN_BG_COLORS = [
  'rgba(255, 255, 255, 1)',
  'rgba(255, 255, 255, 0.8)',
  'rgba(0, 0, 0, 0)',
  'rgba(19, 19, 19, 0.95)',
  'rgba(0, 0, 0, 1)',
] as const

const hexToRgb = (hex: string): string | null => {
  const value = hex.trim().replace(/^#/, '')
  if (!/^[0-9a-fA-F]{3}$|^[0-9a-fA-F]{6}$/.test(value)) return null
  const full = value.length === 3
    ? value.split('').map(c => c + c).join('')
    : value
  const r = parseInt(full.slice(0, 2), 16)
  const g = parseInt(full.slice(2, 4), 16)
  const b = parseInt(full.slice(4, 6), 16)
  return `rgb(${r}, ${g}, ${b})`
}

const Swatch = ({ color, active, onPress }: {
  color: string
  active: boolean
  onPress: () => void
}) => {
  const theme = useTheme()
  return (
    <TouchableOpacity style={styles.swatchWrap} activeOpacity={0.6} onPress={onPress}>
      <View style={{
        ...styles.swatch,
        backgroundColor: color,
        borderColor: active ? theme['c-primary'] : theme['c-border-background'],
        borderWidth: active ? 2.5 : 1,
      }} />
    </TouchableOpacity>
  )
}

const SwatchRow = ({ colors, value, onChange }: {
  colors: readonly string[]
  value: string
  onChange: (color: string) => void
}) => {
  return (
    <View style={styles.swatchRow}>
      {
        colors.map(color => (
          <Swatch key={color} color={color} active={color == value} onPress={() => { onChange(color) }} />
        ))
      }
    </View>
  )
}

export default memo(forwardRef<ThemeEditModalType, Props>(({ onSaved }, ref) => {
  const t = useI18n()
  const theme = useTheme()
  const dialogRef = useRef<DialogType>(null)
  const [name, setName] = useState('')
  const [primary, setPrimary] = useState<string>(PRIMARY_COLORS[0])
  const [font, setFont] = useState<string>(FONT_COLORS[0])
  const [mainBg, setMainBg] = useState<string>(MAIN_BG_COLORS[0])
  const [isDark, setIsDark] = useState(false)
  const [hex, setHex] = useState('')

  useImperativeHandle(ref, () => ({
    show() {
      setName('')
      setPrimary(PRIMARY_COLORS[0])
      setFont(FONT_COLORS[0])
      setMainBg(MAIN_BG_COLORS[0])
      setIsDark(false)
      setHex('')
      dialogRef.current?.setVisible(true)
    },
  }))

  const handleHexChange = useCallback((text: string) => {
    setHex(text)
    const color = hexToRgb(text)
    if (color) setPrimary(color)
  }, [])

  const handleDarkChange = useCallback((dark: boolean) => {
    setIsDark(dark)
    setFont(dark ? 'rgb(229, 229, 229)' : 'rgb(33, 33, 33)')
    setMainBg(dark ? 'rgba(19, 19, 19, 0.95)' : 'rgba(255, 255, 255, 1)')
  }, [])

  const handleSave = useCallback(() => {
    const themeName = name.trim()
    if (!themeName) {
      toast(t('theme_edit_name_empty'))
      return
    }
    onSaved(createCustomTheme({
      name: themeName,
      primaryColor: primary,
      fontColor: font,
      mainBackground: mainBg,
      isDark,
    }))
    dialogRef.current?.setVisible(false)
  }, [name, primary, font, mainBg, isDark, onSaved, t])

  return (
    <Dialog ref={dialogRef} title={t('theme_edit_title')} bgHide={false} keyHide={false}>
      <ScrollView style={styles.body} keyboardShouldPersistTaps="handled">
        <View style={styles.item}>
          <Text style={styles.label} size={13} color={theme['c-primary-font']}>{t('theme_edit_name')}</Text>
          <View style={{ ...styles.inputWrap, backgroundColor: theme['c-primary-background'], borderColor: theme['c-border-background'] }}>
            <Input value={name} onChangeText={setName} placeholder={t('theme_edit_name_placeholder')} placeholderTextColor={theme['c-450']} size={13} />
          </View>
        </View>

        <View style={styles.item}>
          <Text style={styles.label} size={13} color={theme['c-primary-font']}>{t('theme_edit_primary')}</Text>
          <SwatchRow colors={PRIMARY_COLORS} value={primary} onChange={setPrimary} />
          <View style={{ ...styles.inputWrap, backgroundColor: theme['c-primary-background'], borderColor: theme['c-border-background'] }}>
            <Input value={hex} onChangeText={handleHexChange} placeholder={t('theme_edit_color_placeholder')} placeholderTextColor={theme['c-450']} size={13} autoCapitalize="none" />
          </View>
        </View>

        <View style={styles.item}>
          <Text style={styles.label} size={13} color={theme['c-primary-font']}>{t('theme_edit_font')}</Text>
          <SwatchRow colors={FONT_COLORS} value={font} onChange={setFont} />
        </View>

        <View style={styles.item}>
          <Text style={styles.label} size={13} color={theme['c-primary-font']}>{t('theme_edit_main_bg')}</Text>
          <SwatchRow colors={MAIN_BG_COLORS} value={mainBg} onChange={setMainBg} />
        </View>

        <View style={styles.item}>
          <CheckBox check={isDark} label={t('theme_edit_is_dark')} onChange={handleDarkChange} />
        </View>

        <View style={styles.footer}>
          <TouchableOpacity style={{ ...styles.btn, backgroundColor: theme['c-button-background'] }} onPress={() => { dialogRef.current?.setVisible(false) }}>
            <Text size={13} color={theme['c-button-font']}>{t('theme_edit_cancel')}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={{ ...styles.btn, backgroundColor: theme['c-primary'] }} onPress={handleSave}>
            <Text size={13} color={theme['c-button-font']}>{t('theme_edit_save')}</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </Dialog>
  )
}))

const styles = createStyle({
  body: {
    paddingHorizontal: 15,
    paddingTop: 12,
    maxHeight: 520,
  },
  item: {
    marginBottom: 14,
  },
  label: {
    marginBottom: 8,
  },
  inputWrap: {
    borderRadius: 4,
    borderWidth: 1,
    paddingHorizontal: 6,
    marginTop: 8,
  },
  swatchRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  swatchWrap: {
    padding: 3,
  },
  swatch: {
    width: 30,
    height: 30,
    borderRadius: 6,
  },
  footer: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    gap: 12,
    paddingBottom: 16,
    paddingTop: 4,
  },
  btn: {
    paddingHorizontal: 16,
    paddingVertical: 9,
    borderRadius: 4,
  },
})
FILE_EOF

# 6. 主题颜色推导
cat > src/theme/themes/createCustomTheme.ts <<'FILE_EOF'
// 自定义主题：从「主题色 + 字体颜色 + 内容区域背景色」推导出整套颜色表
// 颜色推导算法与 theme/themes/utils.js 中的 createThemeColors 保持一致

interface RGBA {
  r: number
  g: number
  b: number
  a?: number
}

const parseColor = (color: string): RGBA => {
  const m = /rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)/i.exec(color)
  if (!m) return { r: 255, g: 255, b: 255, a: 1 }
  return {
    r: Number(m[1]),
    g: Number(m[2]),
    b: Number(m[3]),
    a: m[4] == null ? undefined : Number(m[4]),
  }
}

// 输出格式与上游 themes.ts 完全一致：rgb(r,g,b) / rgba(r,g,b,a) / rgba(r, g, b, 0.00)
const toColor = ({ r, g, b, a }: RGBA, alphaFixed = false) => {
  const rr = Math.round(r)
  const gg = Math.round(g)
  const bb = Math.round(b)
  if (a == null) return `rgb(${rr},${gg},${bb})`
  return alphaFixed
    ? `rgba(${rr}, ${gg}, ${bb}, ${a.toFixed(2)})`
    : `rgba(${rr},${gg},${bb}, ${a})`
}

// p: -1.0 ~ 1.0，负为变暗，正为变亮
const linearShade = (p: number, color: string): string => {
  const c = parseColor(color)
  const isDark = p < 0
  const t = isDark ? 0 : 255 * p
  const rate = isDark ? 1 + p : 1 - p
  return toColor({ r: c.r * rate + t, g: c.g * rate + t, b: c.b * rate + t, a: c.a })
}

// p: 0 ~ 1，越大越透明
const alphaShade = (p: number, color: string): string => {
  const c = parseColor(color)
  const base = c.a ?? 1
  let alpha = base - base * p
  alpha = Math.min(1, Math.max(0, alpha))
  return toColor({ r: c.r, g: c.g, b: c.b, a: alpha }, true)
}

const createFontColors = (fontColor: string, isDark: boolean) => {
  const colors: Record<string, string> = { 'c-1000': fontColor }
  if (isDark) {
    // 暗色主题：逐级基于上一个颜色变暗
    let preColor = fontColor
    for (let i = 1; i < 21; i += 1) {
      preColor = linearShade(-0.05, preColor)
      colors[`c-${String(1000 - 50 * i).padStart(3, '0')}`] = preColor
    }
  } else {
    // 亮色主题：每一级都基于基础色变亮
    for (let i = 1; i < 21; i += 1) {
      colors[`c-${String(1000 - 50 * i).padStart(3, '0')}`] = linearShade(0.05 * i, fontColor)
    }
  }
  return colors
}

export const createThemeColors = (primaryColor: string, fontColor: string, isDark: boolean) => {
  const colors: Record<string, string> = {
    'c-primary': primaryColor,
  }

  let preColor = primaryColor
  for (let i = 1; i < 11; i += 1) {
    preColor = linearShade(isDark ? 0.2 : -0.1, preColor)
    colors[`c-primary-dark-${i * 100}`] = preColor
    for (let j = 1; j < 10; j += 1) {
      colors[`c-primary-dark-${i * 100}-alpha-${j * 100}`] = alphaShade(0.1 * j, preColor)
      colors[`c-primary-alpha-${j * 100}`] = alphaShade(0.1 * j, primaryColor)
    }
  }

  preColor = primaryColor
  for (let i = 1; i < 10; i += 1) {
    preColor = linearShade(isDark ? -0.1 : 0.2, preColor)
    colors[`c-primary-light-${i * 100}`] = preColor
    for (let j = 1; j < 10; j += 1) {
      colors[`c-primary-light-${i * 100}-alpha-${j * 100}`] = alphaShade(0.1 * j, preColor)
    }
  }

  preColor = linearShade(isDark ? -0.35 : 1, preColor)
  colors['c-primary-light-1000'] = preColor
  for (let j = 1; j < 10; j += 1) {
    colors[`c-primary-light-1000-alpha-${j * 100}`] = alphaShade(0.1 * j, preColor)
  }

  colors['c-theme'] = isDark ? colors['c-primary-light-900'] : primaryColor

  return { ...colors, ...createFontColors(fontColor, isDark) }
}

export interface CustomThemeOptions {
  name: string
  /** 主题色 rgb(...) */
  primaryColor: string
  /** 字体颜色 rgb(...) */
  fontColor: string
  /** 内容区域背景色 rgba(...) */
  mainBackground: string
  isDark: boolean
}

export const createCustomTheme = ({ name, primaryColor, fontColor, mainBackground, isDark }: CustomThemeOptions): LX.Theme => {
  return {
    id: `custom_${Date.now()}`,
    name,
    isDark,
    isCustom: true,
    config: {
      themeColors: createThemeColors(primaryColor, fontColor, isDark),
      extInfo: {
        'c-app-background': mainBackground,
        'c-main-background': mainBackground,
        'bg-image': '',
        'bg-image-position': 'center',
        'bg-image-size': 'cover',
        'c-badge-primary': 'var(c-primary)',
        'c-badge-secondary': 'var(c-primary-light-100)',
        'c-badge-tertiary': 'var(c-primary-light-100)',
      },
    },
  } as unknown as LX.Theme
}
FILE_EOF

# 7. 类型、默认值、包名、应用名、多语言词条
node - <<'NODE_EOF'
const fs = require('fs')

const patchText = (file, from, to, doneFlag) => {
  const s = fs.readFileSync(file, 'utf8')
  if (doneFlag && s.includes(doneFlag)) {
    console.log('   skipped (已应用)', file)
    return
  }
  if (!s.includes(from)) throw new Error('锚点缺失 ' + file + ' :: ' + from.slice(0, 48).replace(/\n/g, '\\n'))
  fs.writeFileSync(file, s.replace(from, to))
  console.log('   patched', file)
}

// 1) 类型定义 src/types/app_setting.d.ts
const typeAnchor = [
  '      /**',
  '       * 字体阴影',
  '       */',
  "      'theme.fontShadow': boolean",
  '',
].join('\n')
const typeAdd = typeAnchor + "\n" + [
  '      /**',
  '       * 自定义背景图片路径（空字符串表示未设置）',
  '       */',
  "      'theme.customBg.path': string",
  '',
  '      /**',
  '       * 自定义背景蒙版透明度 0-100',
  '       */',
  "      'theme.customBg.maskAlpha': number",
  '',
  '      /**',
  '       * 自定义背景蒙版颜色',
  '       */',
  "      'theme.customBg.maskColor': string",
  '',
  '      /**',
  '       * 自定义背景模糊半径（0 表示不模糊）',
  '       */',
  "      'theme.customBg.blur': number",
  '',
  '      /**',
  '       * 自定义背景填充方式',
  '       */',
  "      'theme.customBg.resizeMode': 'cover' | 'contain' | 'stretch'",
  '',
].join('\n')
patchText('src/types/app_setting.d.ts', typeAnchor, typeAdd, "'theme.customBg.path'")

// 2) 默认值 src/config/defaultSetting.ts
patchText(
  'src/config/defaultSetting.ts',
  "  'theme.fontShadow': false,\n",
  [
    "  'theme.fontShadow': false,",
    "  'theme.customBg.path': '',",
    "  'theme.customBg.maskAlpha': 40,",
    "  'theme.customBg.maskColor': 'rgba(0, 0, 0, 1)',",
    "  'theme.customBg.blur': 0,",
    "  'theme.customBg.resizeMode': 'cover',",
    '',
  ].join('\n'),
  "'theme.customBg.path'",
)

// 3) 包名 android/app/build.gradle
patchText(
  'android/app/build.gradle',
  '        applicationId "cn.toside.music.mobile"',
  '        applicationId "cn.toside.music.mobile.custombg"',
  'custombg',
)

// 4) 应用名
patchText(
  'android/app/src/main/res/values/strings.xml',
  '<string name="app_name">LX Music</string>',
  '<string name="app_name">洛雪·自定义背景</string>',
  '自定义背景',
)

// 5) 多语言词条（逐个补齐缺失的键，可重复执行）
const dict = {
  'zh-cn': {
    setting_custom_bg: '自定义背景',
    setting_custom_bg_select: '选择背景图片',
    setting_custom_bg_change: '更换图片',
    setting_custom_bg_clear: '清除背景',
    setting_custom_bg_applied: '背景已更新',
    setting_custom_bg_cleared: '已清除自定义背景',
    setting_custom_bg_tip_on: '当前使用自定义背景图片',
    setting_custom_bg_tip_off: '未设置，当前使用主题背景',
    setting_custom_bg_mask_alpha: '蒙版透明度',
    setting_custom_bg_mask_color: '蒙版颜色',
    setting_custom_bg_mask_color_black: '黑色',
    setting_custom_bg_mask_color_white: '白色',
    setting_custom_bg_resize: '填充方式',
    setting_custom_bg_resize_cover: '铺满',
    setting_custom_bg_resize_contain: '完整显示',
    setting_custom_bg_resize_stretch: '拉伸',
    setting_custom_bg_blur: '背景模糊',
    setting_theme_add: '添加主题',
    theme_edit_title: '添加主题',
    theme_edit_name: '主题名称',
    theme_edit_name_placeholder: '给主题起个名字',
    theme_edit_name_empty: '主题名称不能为空',
    theme_edit_primary: '主题色',
    theme_edit_color_placeholder: '自定义颜色，如 #4daf7c',
    theme_edit_font: '字体颜色',
    theme_edit_main_bg: '内容区域背景色',
    theme_edit_is_dark: '暗色主题',
    theme_edit_save: '保存',
    theme_edit_cancel: '取消',
    theme_edit_saved: '主题已保存',
    theme_delete_confirm: '确定删除主题「{name}」吗？',
    theme_deleted: '主题已删除',
  },
  'zh-tw': {
    setting_custom_bg: '自訂背景',
    setting_custom_bg_select: '選擇背景圖片',
    setting_custom_bg_change: '更換圖片',
    setting_custom_bg_clear: '清除背景',
    setting_custom_bg_applied: '背景已更新',
    setting_custom_bg_cleared: '已清除自訂背景',
    setting_custom_bg_tip_on: '目前使用自訂背景圖片',
    setting_custom_bg_tip_off: '未設定，目前使用主題背景',
    setting_custom_bg_mask_alpha: '遮罩透明度',
    setting_custom_bg_mask_color: '遮罩顏色',
    setting_custom_bg_mask_color_black: '黑色',
    setting_custom_bg_mask_color_white: '白色',
    setting_custom_bg_resize: '填滿方式',
    setting_custom_bg_resize_cover: '填滿',
    setting_custom_bg_resize_contain: '完整顯示',
    setting_custom_bg_resize_stretch: '拉伸',
    setting_custom_bg_blur: '背景模糊',
    setting_theme_add: '新增主題',
    theme_edit_title: '新增主題',
    theme_edit_name: '主題名稱',
    theme_edit_name_placeholder: '給主題取個名字',
    theme_edit_name_empty: '主題名稱不能為空',
    theme_edit_primary: '主題色',
    theme_edit_color_placeholder: '自訂顏色，如 #4daf7c',
    theme_edit_font: '字體顏色',
    theme_edit_main_bg: '內容區域背景色',
    theme_edit_is_dark: '暗色主題',
    theme_edit_save: '儲存',
    theme_edit_cancel: '取消',
    theme_edit_saved: '主題已儲存',
    theme_delete_confirm: '確定刪除主題「{name}」嗎？',
    theme_deleted: '主題已刪除',
  },
  'en-us': {
    setting_custom_bg: 'Custom background',
    setting_custom_bg_select: 'Select background image',
    setting_custom_bg_change: 'Change image',
    setting_custom_bg_clear: 'Clear background',
    setting_custom_bg_applied: 'Background updated',
    setting_custom_bg_cleared: 'Custom background cleared',
    setting_custom_bg_tip_on: 'Using custom background image',
    setting_custom_bg_tip_off: 'Not set, using theme background',
    setting_custom_bg_mask_alpha: 'Mask opacity',
    setting_custom_bg_mask_color: 'Mask color',
    setting_custom_bg_mask_color_black: 'Black',
    setting_custom_bg_mask_color_white: 'White',
    setting_custom_bg_resize: 'Fill mode',
    setting_custom_bg_resize_cover: 'Cover',
    setting_custom_bg_resize_contain: 'Contain',
    setting_custom_bg_resize_stretch: 'Stretch',
    setting_custom_bg_blur: 'Blur background',
    setting_theme_add: 'Add theme',
    theme_edit_title: 'Add theme',
    theme_edit_name: 'Theme name',
    theme_edit_name_placeholder: 'Name this theme',
    theme_edit_name_empty: 'Theme name cannot be empty',
    theme_edit_primary: 'Theme color',
    theme_edit_color_placeholder: 'Custom color, e.g. #4daf7c',
    theme_edit_font: 'Font color',
    theme_edit_main_bg: 'Content background',
    theme_edit_is_dark: 'Dark theme',
    theme_edit_save: 'Save',
    theme_edit_cancel: 'Cancel',
    theme_edit_saved: 'Theme saved',
    theme_delete_confirm: 'Delete theme "{name}"?',
    theme_deleted: 'Theme deleted',
  },
}

for (const lang of Object.keys(dict)) {
  const file = 'src/lang/' + lang + '.json'
  const lines = fs.readFileSync(file, 'utf8').split('\n')
  const keys = Object.keys(dict[lang])
  const missing = keys.filter(k => !lines.some(l => l.includes(JSON.stringify(k) + ':')))
  if (!missing.length) {
    console.log('   skipped (词条已存在)', file)
    continue
  }
  const idx = lines.findIndex(l => l.includes('"setting_basic_theme_more_btn_show"'))
  if (idx < 0) throw new Error('锚点缺失 ' + file)
  const add = missing.map(k => '  ' + JSON.stringify(k) + ': ' + JSON.stringify(dict[lang][k]) + ',')
  lines.splice(idx + 1, 0, ...add)
  fs.writeFileSync(file, lines.join('\n'))
  JSON.parse(fs.readFileSync(file, 'utf8'))
  console.log('   patched', file, '(+' + missing.length + ' 词条)')
}

// 6) 主题存储健壮性（保存/删除前确保已加载用户主题）
patchText(
  'src/theme/themes/index.ts',
  "export const saveTheme = async(theme: LX.Theme) => {\n  const targetTheme",
  "export const saveTheme = async(theme: LX.Theme) => {\n  userThemes ??= await getUserTheme()\n  const targetTheme",
  "userThemes ??= await getUserTheme()\n  const targetTheme",
)
patchText(
  'src/theme/themes/index.ts',
  "export const removeTheme = async(id: string) => {\n  const index",
  "export const removeTheme = async(id: string) => {\n  userThemes ??= await getUserTheme()\n  const index",
  "userThemes ??= await getUserTheme()\n  const index",
)
NODE_EOF

echo "==> 补丁应用完成"
node -e '
const fs = require("fs")
const files = [
  "src/screens/Home/Views/Setting/settings/Theme/CustomBg.tsx",
  "src/screens/Home/Views/Setting/settings/Theme/Theme.tsx",
  "src/screens/Home/Views/Setting/settings/Theme/index.tsx",
  "src/components/PageContent.tsx",
  "src/components/ThemeEditModal.tsx",
  "src/theme/themes/createCustomTheme.ts",
  "src/config/defaultSetting.ts",
  "src/types/app_setting.d.ts",
]
for (const f of files) console.log("   ok", f)
const g = fs.readFileSync("android/app/build.gradle", "utf8")
console.log("   applicationId =", /applicationId "([^"]+)"/.exec(g)[1])
const zh = fs.readFileSync("src/lang/zh-cn.json", "utf8")
console.log("   自定义背景词条 =", zh.includes("setting_custom_bg_mask_alpha"))
console.log("   自定义主题词条 =", zh.includes("theme_edit_saved"))
'
