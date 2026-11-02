#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 洛雪音乐 移动版（lx-music-mobile v1.9.2）——「自定义背景」功能补丁
#
# 用法：把本脚本放到仓库根目录的 build/ 下，然后在源码根目录执行
#     bash build/custom-bg-patch.sh [源码目录]      # 默认 lx
#
# 改动内容：
#   * 设置 → 主题 新增「自定义背景」：选择图片、蒙版透明度、蒙版颜色、
#     填充方式、背景模糊、清除
#   * 主界面/播放详情/评论页背景改用自定义图片（不设置时保持原样）
#   * 包名改为 cn.toside.music.mobile.custombg（可与官方版、IKUN 版共存）
#   * 应用名改为「洛雪·自定义背景」
# ---------------------------------------------------------------------------
set -euo pipefail

TARGET="${1:-lx}"
cd "$TARGET"

if [ ! -f package.json ] || ! grep -q '"name": "lx-music-mobile"' package.json; then
  echo "!! 当前目录不是 lx-music-mobile 源码根目录: $(pwd)" >&2
  exit 1
fi

echo "==> 目标源码: $(pwd)"

# ---------------------------------------------------------------------------
# 1. 新增设置界面组件
# ---------------------------------------------------------------------------
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
const saveCustomBg = async(from: string) => {
  const dir = CUSTOM_BG_DIR
  const ext = extname(from) || 'jpg'
  const to = dir + '/bg.' + ext
  try {
    if (!await RNFS.exists(dir)) await RNFS.mkdir(dir)
    if (await RNFS.exists(to)) await RNFS.unlink(to)
    await RNFS.copyFile(from, to)
    updateSetting({ 'theme.customBg.path': to })
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
      void saveCustomBg(selectedPath).then(() => {
        toast(t('setting_custom_bg_applied'))
      })
    })
  }, [t])

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

# ---------------------------------------------------------------------------
# 2. 主界面背景渲染（支持自定义背景 + 蒙版 + 模糊 + 填充方式）
# ---------------------------------------------------------------------------
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
          style={{ position: 'absolute', left: 0, top: 0, height: windowSize.height, width: windowSize.width, backgroundColor: theme['c-content-background'] }}
          source={{ uri: getImageUri(customBgPath) }}
          resizeMode={customBgResizeMode}
          blurRadius={customBgBlur}
        >
        </ImageBackground>
        <View style={{
          position: 'absolute',
          left: 0,
          top: 0,
          height: windowSize.height,
          width: windowSize.width,
          backgroundColor: customBgMaskColor,
          opacity: customBgMaskAlpha / 100,
        }}></View>
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

# ---------------------------------------------------------------------------
# 3. 主题设置区注册「自定义背景」
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 4. 其余文件用脚本精确插入
# ---------------------------------------------------------------------------
node - <<'NODE_EOF'
const fs = require('fs')

const patchText = (file, from, to) => {
  const s = fs.readFileSync(file, 'utf8')
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
patchText('src/types/app_setting.d.ts', typeAnchor, typeAdd)

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
)

// 3) 包名 android/app/build.gradle
patchText(
  'android/app/build.gradle',
  '        applicationId "cn.toside.music.mobile"',
  '        applicationId "cn.toside.music.mobile.custombg"',
)

// 4) 应用名
patchText(
  'android/app/src/main/res/values/strings.xml',
  '<string name="app_name">LX Music</string>',
  '<string name="app_name">洛雪·自定义背景</string>',
)

// 5) 多语言词条
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
  },
}

for (const lang of Object.keys(dict)) {
  const file = 'src/lang/' + lang + '.json'
  const s = fs.readFileSync(file, 'utf8')
  if (s.includes('setting_custom_bg_mask_alpha')) {
    console.log('   skipped (已存在词条)', file)
    continue
  }
  const lines = s.split('\n')
  const idx = lines.findIndex(l => l.includes('"setting_basic_theme_more_btn_show"'))
  if (idx < 0) throw new Error('锚点缺失 ' + file)
  const add = Object.keys(dict[lang]).map(k => '  ' + JSON.stringify(k) + ': ' + JSON.stringify(dict[lang][k]) + ',')
  lines.splice(idx + 1, 0, ...add)
  fs.writeFileSync(file, lines.join('\n'))
  JSON.parse(fs.readFileSync(file, 'utf8'))
  console.log('   patched', file)
}
NODE_EOF

echo "==> 补丁应用完成"
node -e '
const fs=require("fs");
const files=["src/screens/Home/Views/Setting/settings/Theme/CustomBg.tsx","src/components/PageContent.tsx","src/screens/Home/Views/Setting/settings/Theme/index.tsx","src/config/defaultSetting.ts","src/types/app_setting.d.ts"];
for(const f of files) console.log("   ok", f);
const g=fs.readFileSync("android/app/build.gradle","utf8");
console.log("   applicationId =", /applicationId "([^"]+)"/.exec(g)[1]);
const d=fs.readFileSync("src/config/defaultSetting.ts","utf8");
console.log("   默认值已写入 =", d.includes("theme.customBg.path"));
'
