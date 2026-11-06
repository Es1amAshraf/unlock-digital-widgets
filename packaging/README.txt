UNLOCK DIGITAL - Desktop Widgets
================================
الإصدار 1.3.0

حزمة تثبيت كاملة لويدجتس سطح المكتب:
  • Dock زجاجي قابل للتخصيص (إضافة/ترتيب/سحب التطبيقات)
  • HUD لمتابعة CPU / RAM / الشبكة / البينج
  • ساعة زجاجية مع الثواني والتاريخ
  • ويدجت الموسيقى (يشتغل مع تشغيل المتصفح)
  • تقويم شهري تفاعلي (اختياري)
  • مؤقّت تركيز 25/5 مع إشعار عند الانتهاء (اختياري)
  • مفكرة سريعة بتتحفظ تلقائيًا (اختياري)
  • مدير ويدجتس: إخفاء/إظهار، قفل المكان، تثبيت فوق النوافذ، وتحريك بنقرة
  • أيقونة في التراي + تشغيل تلقائي + Watchdog يرجعهم لو اتقفلوا

المتطلبات
---------
  • Windows 10 أو 11
  • PowerShell 5.1 (مدمج في ويندوز)
  • لا يحتاج صلاحيات Administrator ولا إنترنت


التثبيت
-------
  1) فك ضغط الحزمة في أي فولدر.
  2) دبل كليك على Install.cmd
     (لو ظهرت رسالة SmartScreen: More info ← Run anyway)
  3) اختار الخيارات اللي تناسبك ثم اضغط Install.
  4) الويدجتس هتشتغل فورًا، وهتلاقي اختصارات في Start Menu تحت UNLOCK DIGITAL.

مكان التثبيت
------------
  %LOCALAPPDATA%\UNLOCK DIGITAL\Widgets
  ملف الإعدادات: widgets.json
  (من Start Menu ← UNLOCK DIGITAL ← Widgets Settings)

خيارات التثبيت
--------------
  [x] Start automatically when I sign in
      تشغيل الويدجتس تلقائيًا مع تسجيل الدخول.

  [x] Keep the widgets running
      Watchdog يفحص كل دقيقة ويرجّع الويدجتس لو اتقفلوا.

  [x] Create Start Menu shortcuts
      اختصارات: Desktop Widgets / Widgets Settings / Uninstall.

  [x] Apply the UNLOCK DIGITAL wallpaper
      يطبّق خلفية الحزمة. عند الإزالة يتم استرجاع الخلفية القديمة تلقائيًا.

  [ ] Apply dark theme + clean taskbar
      اختياري: ثيم غامق + شريط مهام نضيف + إخفاء أيقونات سطح المكتب.
      (بيعيد تشغيل Explorer مرة واحدة) - يمكن استرجاعه من الـ Uninstaller.


الاستخدام السريع
----------------
  • سحب أي ويدجت بالماوس ينقلها، والمكان بيتحفظ تلقائيًا.
  • مدير الويدجتس: كليك يمين على الدوك ← Manage widgets… (أو من التراي).
      HIDE / SHOW   = إخفاء أو إظهار الويدجت
      LOCK / UNLOCK = قفل المكان (يمنع السحب بالماوس)
      TOP ON / OFF  = تثبيت الويدجت فوق كل النوافذ
      MOVE          = تحريك: حرّك الماوس وبعدين كليك لتثبيت المكان (Esc يلغي)
      Show all      = إظهار كل الويدجتس
      Reset positions = رجوع كل الويدجتس لأماكنها الافتراضية
  • كليك يمين على الساعة: ثواني / 24 ساعة / Always on top / Lock position / Move widget / إعادة ضبط المكان.
  • كليك يمين على التقويم: بداية الأسبوع يوم الإثنين / Always on top / Lock position / Move widget / إعادة ضبط المكان.
  • كليك يمين على مؤقّت التركيز: 25/5 أو 50/10 أو 90/15 / Always on top / Lock position / Move widget / إعادة ضبط المكان.
  • كليك يمين على المفكرة: Always on top / Lock position / Move widget / مسح الملاحظة / إعادة ضبط المكان.
  • المفكرة بتتحفظ لوحدها في notes.txt، و Ctrl+S بيحفظ فورًا.
  • كليك يمين على الـ Dock: Manage widgets، إدارة التطبيقات، Always on top، Auto-hide.
  • أيقونة التراي: إظهار/إخفاء الويدجتس، Manage widgets، إدارة تطبيقات الدوك، بدء جلسة تركيز، إعادة التشغيل.


الإزالة
-------
  1) Settings ← Apps ← Installed apps ← UNLOCK DIGITAL Desktop Widgets ← Uninstall
  2) أو Start Menu ← UNLOCK DIGITAL ← Uninstall Widgets
  3) أو دبل كليك على Uninstall.cmd جوّه فولدر التثبيت

  تقدر تختار الاحتفاظ بملف الإعدادات widgets.json وملف الملاحظات notes.txt لو هتعيد التثبيت.


سطر الأوامر (اختياري)
---------------------
  تثبيت صامت:
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File setup\Install.ps1 -Silent -AutoInstall

  إزالة صامتة:
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\UNLOCK DIGITAL\Widgets\Uninstall.ps1" -Silent -AutoUninstall

  خيارات إضافية للتثبيت:
    -InstallDir "<path>"   مكان مخصص
    -NoTasks               بدون تشغيل تلقائي / Watchdog
    -NoShortcuts           بدون اختصارات
    -NoWallpaper           بدون خلفية
    -NoLaunch              بدون تشغيل بعد التثبيت
    -Taskbar               تطبيق الثيم وشريط المهام

  تشغيل مباشر للويدجتس:
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\UNLOCK DIGITAL\Widgets\ProDesktopWidgets.ps1"
    أضف -WidgetsManager لفتح مدير الويدجتس مع التشغيل.


التحديث
-------
  شغّل Install.cmd تاني فوق النسخة القديمة: بيحدّث الملفات ويسيب إعداداتك كما هي.


نقل الإعدادات لجهاز تاني
------------------------
  انسخ ملف widgets.json من فولدر التثبيت القديم إلى نفس المكان في الجهاز الجديد.
  (تطبيقات الدوك اللي مش متثبتة على الجهاز الجديد مش هتشتغل - تقدر تشيلها من
  كليك يمين على الدوك ← Manage dock apps)


المظهر والإعدادات (جديد في 1.3.0)
---------------------------------
  من مدير الويدجتس (كليك يمين على الدوك ← Manage widgets) هتلاقي قسم APPEARANCE:
  • Theme: 5 ثيمات (Midnight / Ocean / Amethyst / Ember / Graphite).
      بيتحفظ فورًا، ومن التراي ← Restart widgets بيتطبق على كل الويدجتس.
  • Opacity: شفافية الويدجتس من 55% لـ 100%.
  • Widget size: 85% / 100% / 115% (الدوك مش بيتأثر).
  • Low power mode: بيبطّئ تحديث الـ HUD لتقليل استهلاك المعالج.
  • Hide during fullscreen apps / games: إخفاء الويدجتس تلقائيًا أثناء الألعاب
      (D3D fullscreen) ووضع العرض، ورجوعها بعد الخروج.
  • Profiles: Work / Focus / Night / Game - تغيير مجموعة الويدجتس الظاهرة بضغطة.

حل المشاكل
----------
  • الويدجتس مش ظاهرة؟
      Start Menu ← UNLOCK DIGITAL ← Desktop Widgets
  • ويدجت معين مختفي؟ من التراي أو الدوك ← Manage widgets ← Show all.
  • ملف اللوج:
      %TEMP%\UNLOCK DIGITAL install.log
  • لو الويدجتس ورا النوافذ: من التراي ← Keep widgets on top، أو من المدير ← TOP ON.
  • ويدجت مش بتتحرك بالسحب؟ افتح المدير واضغط LOCK/UNLOCK (أو شيل علامة Lock position).
  • إعادة ضبط كل الإعدادات: من التراي ← Reset widget positions، أو امسح widgets.json
    والويدجتس هتولّد إعدادات جديدة.


محتويات الحزمة
--------------
  Install.cmd              مشغّل التثبيت
  README.txt               هذا الملف
  setup\Install.ps1        منطق التثبيت + الواجهة
  setup\Uninstall.ps1      منطق الإزالة + الواجهة
  payload\                 ملفات الويدجتس + الأيقونة + الخلفية
  extras\                  سكربتات اختيارية للثيم وشريط المهام
