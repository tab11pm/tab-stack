set -e
S=/home/kisa/Projects/tab-stack/dotfiles/config/shoji-shell
L=$HOME/.config/shoji-shell
cp $S/KolonkaWidget.qml $S/kolonka-widget.py $L/
cp $S/icons/{speaker,mic,mic-off,terminal,refresh,volume-low,shuffle,repeat,repeat-1,list-music}.svg $L/icons/
python3 - <<'PY'
import os
L=os.path.expanduser("~/.config/shoji-shell/")
def sub(p,a,b):
    s=open(L+p).read()
    if b in s: return
    assert a in s,(p,a); open(L+p,"w").write(s.replace(a,a+b,1))
sub("qmldir","WidgetSurface 1.0 WidgetSurface.qml\n","KolonkaWidget 1.0 KolonkaWidget.qml\n")
import re
st=open(L+"WidgetLayoutState.js").read()
open(L+"WidgetLayoutState.js","w").write(re.sub(r'    \{ id: "kolonka".*\n', "", st))  # drop an older size
sub("WidgetLayoutState.js",'    { id: "weather", label: "Погода", width: 286, height: 160 },\n','    { id: "kolonka", label: "Колонка Яндекс", width: 340, height: 430 },\n')
sub("WallpaperScreen.qml","            Region { item: githubLoader.active && githubLoader.enabled ? githubLoader : null }\n","            Region { item: kolonkaLoader.active && kolonkaLoader.enabled ? kolonkaLoader : null }\n")
sub("WallpaperScreen.qml","            sourceComponent: GithubWidget {}\n        }\n","        WidgetWaveLoader {\n            id: kolonkaLoader\n            widgetId: \"kolonka\"; output: root.output; transition: wallpaperTransition\n            sourceComponent: KolonkaWidget {}\n        }\n")
PY
echo deployed
