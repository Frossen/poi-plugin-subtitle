{_, SERVER_HOSTNAME} = window
Promise = require 'bluebird'
path = require 'path'
async = Promise.coroutine
fs = Promise.promisifyAll require('fs-extra'), { multiArgs: true }
request = Promise.promisifyAll require('request'), { multiArgs: true }
{Traditionalized} = require './traditionalized'
dbg.extra('subtitlesAudioResponse')
voiceMap = {}
shipgraph = {}
subtitles = {}
subtitlesI18nPath = {}
subtitlesBackupPath = {}
timeoutHandle = 0
REMOTE_HOST = 'http://api.kcwiki.moe/subtitles'
langs = ['zh-CN', 'zh-TW', 'ja-JP']
i18nSubtitleBaseDir = path.join(APPDATA_PATH, 'poi-plugin-subtitle', 'i18n')
subtitlesI18nPath[lang] = path.join(i18nSubtitleBaseDir, "#{lang}.json") for lang in langs
subtitlesBackupPath[lang] = path.join(__dirname, 'data', "#{lang}.json") for lang in langs
voiceKey = [604825,607300,613847,615318,624009,631856,635451,637218,640529,643036,652687,658008,662481,669598,675545,685034,687703,696444,702593,703894,711191,714166,720579,728970,738675,740918,743009,747240,750347,759846,764051,770064,773457,779858,786843,790526,799973,803260,808441,816028,825381,827516,832463,837868,843091,852548,858315,867580,875771,879698,882759,885564,888837,896168]
convertFilename = (shipId, voiceId) ->
  return (shipId + 7) * 17 * (voiceKey[voiceId] - voiceKey[voiceId - 1]) % 99173 + 100000
for shipNo in [1..500]
  voiceMap[shipNo] = {}
  voiceMap[shipNo][convertFilename(shipNo,i)] = i for i in [1..voiceKey.length]

__ = i18n["poi-plugin-subtitle"].__.bind(i18n["poi-plugin-subtitle"])
___ = {} # i18n for subtitle data

initSubtitlesI18n = ->
  # Current not supprot for en-US and ja-JP, set default to zh-TW
  if i18n["poi-plugin-subtitle"].locale not in langs
    i18n["poi-plugin-subtitle"].setLocale 'ja-JP'
    locale = 'ja-JP'
  else
    locale = i18n["poi-plugin-subtitle"].locale
  i18n['poi-plugin-subtitle-data'] = new(require 'i18n-2')
    locales: langs,
    defaultLocale: 'ja-JP',
    directory: i18nSubtitleBaseDir,
    devMode: false,
    extension: '.json'
  i18n['poi-plugin-subtitle-data'].setLocale(locale)
  ___ = i18n["poi-plugin-subtitle-data"].__.bind(i18n["poi-plugin-subtitle-data"])

loadSubtitles = async (_path) ->
  err = yield fs.ensureFileAsync _path
  data = yield fs.readFileAsync _path
  data = "{}" if not data or data.length is 0
  JSON.parse data

loadBackupSubtitles = async (locale) ->
  abbr = locale[...2]
  if abbr is 'zh'
    dataBackup = yield fs.readFileAsync subtitlesBackupPath['zh-CN']
    subtitlesBackup = JSON.parse dataBackup
    if not subtitles['zh-CN']?.version or +subtitles['zh-CN']?.version < +subtitlesBackup?.version or not subtitles['zh-TW']?.version
      data = dataBackup
      subtitles['zh-CN'] = subtitlesBackup
      err = yield fs.writeFileAsync subtitlesI18nPath['zh-CN'], data
      # Convert backup subtitle to zh-TW and save
      subtitles['zh-TW'] = {}
      for shipIdOrSth, value of subtitlesBackup
        if typeof value isnt 'object'
          subtitles['zh-TW'][shipIdOrSth] = value
        else
          subtitles['zh-TW'][shipIdOrSth] = {} unless subtitles['zh-TW'][shipIdOrSth]
          subtitles['zh-TW'][shipIdOrSth][voiceId] = Traditionalized(text) for voiceId, text of value
      err = yield fs.writeFileAsync subtitlesI18nPath['zh-TW'], JSON.stringify(subtitles['zh-TW'], null, '\t')
  else
    dataBackup = yield fs.readFileAsync subtitlesBackupPath[locale]
    subtitlesBackup = JSON.parse dataBackup
    if not subtitles[locale]?.version or +subtitles[locale]?.version < +subtitlesBackup?.version
      data = dataBackup
      subtitles[locale] = subtitlesBackup
      err = yield fs.writeFileAsync subtitlesI18nPath[locale], data
  console.error err if err
  dataBackup

getSubtitles = async () ->
  dataBackup = {}
  # Load I18n Data
  for lang in langs
    continue if lang is 'zh-TW'
    subtitles[lang] = yield loadSubtitles(subtitlesI18nPath[lang])
    # Load backup subtitle
    dataBackup[lang] = yield loadBackupSubtitles(lang)
  # Update subtitle data from remote server
  if i18n["poi-plugin-subtitle"].locale not in langs
    locale = 'ja-JP'
  else
    locale = i18n["poi-plugin-subtitle"].locale
  abbr = locale[...2]
  abbr = 'jp' if abbr is 'ja'
  url = if abbr is 'zh' then "#{REMOTE_HOST}/diff/#{subtitles['zh-CN'].version}"  else "#{REMOTE_HOST}/#{abbr}/diff/#{subtitles[locale].version}"
  try
    [response, repData] = yield request.getAsync url
    throw "获取字幕数据失败" unless repData
    rep = JSON.parse repData
    throw "字幕数据异常：#{rep.reason}" if rep.result is 'error'
    if rep.version
      for shipIdOrSth,value of rep
        if abbr is 'zh'
          if typeof value isnt "object"
            subtitles[lang][shipIdOrSth] = value for lang in ['zh-CN', 'zh-TW']
          else
            for lang in ['zh-CN', 'zh-TW']
              subtitles[lang][shipIdOrSth] = {} unless subtitles[lang][shipIdOrSth]
            for voiceId, text of value
              subtitles['zh-CN'][shipIdOrSth][voiceId] = text
              subtitles['zh-TW'][shipIdOrSth][voiceId] = Traditionalized(text)
        else
          if typeof value isnt "object"
            subtitles[locale][shipIdOrSth] = value
          else
            subtitles[locale][shipIdOrSth] = {} unless subtitles[locale][shipIdOrSth]
            for voiceId, text of value
              subtitles[locale][shipIdOrSth][voiceId] = text
      version = if abbr is 'zh' then subtitles['zh-CN'].version else subtitles[locale].version
      window.success "#{__('Update Success')}(#{version})",
        stickyFor: 3000
    for lang in langs
      err = yield fs.writeFileAsync subtitlesI18nPath[lang], JSON.stringify(subtitles[lang], null, '\t')
      throw err if err
  catch e
    if e instanceof Error
      console.error "#{e.name}: #{e.message}"
    else
      console.error e
    if locale isnt 'zh-TW'
      err = yield fs.writeFileAsync subtitlesI18nPath[locale], dataBackup[locale]
      console.error err if err
      subtitles[locale] = JSON.parse dataBackup[locale]
    # window.warn "语音字幕自动更新失败，请联系有关开发人员，并手动更新插件以更新字幕数据",
    #   stickyFor: 5000
  finally
    initSubtitlesI18n()
    return

initialize = (e) ->
  if window.getStore?
    api_mst_shipgraph = window.getStore('const.$shipgraph')
  else
    return if !localStorage.start2Body?
    {api_mst_shipgraph} = JSON.parse localStorage.start2Body
  {_ships, _decks, _teitokuLv} = window
  shipgraph[ship.api_filename] = ship.api_id for ship in api_mst_shipgraph
  getSubtitles()

alert = (text, prior, stickyFor) ->
  window.log "#{text}",
    priority : prior,
    stickyFor: stickyFor

handleGameResponse = (e) ->
  clearTimeout(timeoutHandle)

handleGetResponseDetails = (e) ->
  prior = 5
  match = /kcs\/sound\/kc(.*?)\/(.*?).mp3/.exec(e.newURL)
  return if not match? or match.length < 3
  console.log e.newURL if dbg.extra('subtitlesAudioResponse').isEnabled()
  [..., shipCode, fileName] = match
  apiId = shipgraph[shipCode]
  return if not apiId
  voiceId = voiceMap[apiId][fileName]
  return if not voiceId
  if i18n["poi-plugin-subtitle"].locale not in langs
    i18n["poi-plugin-subtitle-data"].setLocale 'ja-JP'
  console.log "#{apiId} #{voiceId}" if dbg.extra('subtitlesAudioResponse').isEnabled()
  subtitle = subtitles['zh-CN'][apiId]?[voiceId]
  console.log "i18n: #{___(apiId+'.'+voiceId)}" if dbg.extra('subtitlesAudioResponse').isEnabled()
  prior = 0 if 8 < voiceId < 11
  shipName = $ships[apiId].api_name
  if voiceId < 30
    if subtitle
      alert "#{shipName}：#{___(apiId+'.'+voiceId)}", prior, 5000
    else
      alert __('Subtitle Miss',shipName), prior, 5000
  else
    now = new Date()
    sharpTime = new Date()
    sharpTime.setHours now.getHours()+1
    sharpTime.setMinutes 0
    sharpTime.setSeconds 0
    sharpTime.setMilliseconds 0
    diff = sharpTime - now
    diff = 0 if diff < 0
    timeoutHandle = setTimeout( ->
      if subtitle
        alert "#{shipName}：#{___(apiId+'.'+voiceId)}", prior, 5000
      else
        alert __('Subtitle Miss',shipName), prior, 5000
    ,diff)

module.exports =
  show: false
  pluginDidLoad: (e) ->
    initialize()
    $('kan-game webview').addEventListener 'did-get-response-details', handleGetResponseDetails
    window.addEventListener 'game.response', handleGameResponse
  pluginWillUnload: (e) ->
    $('kan-game webview').removeEventListener 'did-get-response-details', handleGetResponseDetails
    window.removeEventListener 'game.response', handleGameResponse
