# UNLOCK DIGITAL Desktop Widgets

<div align="center">

![Version](https://img.shields.io/badge/version-1.3.0-blue.svg?style=for-the-badge)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE.svg?style=for-the-badge&logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6.svg?style=for-the-badge&logo=windows&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)

**حزمة ويدجتس سطح مكتب زجاجية متكاملة واحترافية لنظام ويندوز 10 و 11**  
A modern, lightweight, glassmorphic desktop customization & widgets suite built natively for Windows.

</div>

---

## 🌟 المميزات الرئيسية (Features)

تتضمن الحزمة 8 ويدجتس قابلة للتخصيص بالكامل ومصممة بنمط زجاجي (Fluent Glass):

1. **الدوك الزجاجي (macOS-style Dock):**
   - شريط تطبيقات انسيابي أسفل الشاشة مع تأثيرات التكبير والتفاعل (Hover Magnification).
   - إمكانية إضافة وسحب وترتيب التطبيقات بسهولة، مع مؤشرات النقاط للبرامج المفتوحة حالياً.
   - البقاء خلف النوافذ النشطة على سطح المكتب دون أن يطفو فوق برامجك أثناء العمل.

2. **شاشة المراقبة اللحظية (System HUD):**
   - متابعة حية لمعدل استهلاك المعالج (CPU)، والذاكرة العشوائية (RAM)، وسرعة نقل الشبكة (Rx / Tx).
   - قياس معدل الاستجابة اللحظي (Ping)، وعرض الـ IP الداخلي والخارجي مع خيار الحجب للأمان.

3. **الساعة الرقمية (Digital Clock):**
   - تصميم زجاجي أنيق مع الثواني، والتاريخ الميلادي، وشارة يوم الأسبوع، ودعم نظام 12/24 ساعة.

4. **الطقس ومواقيت الصلاة الدقيقة (Weather & Cairo Prayer Times):**
   - جلب مباشر لبيانات الطقس (درجة الحرارة، نسبة الرطوبة، وحالة الجو) عبر Open-Meteo.
   - حساب دقيق لمواقيت الصلاة الخمس بالقاهرة (هيئة المساحة المصرية - طريقة 5) مع التاريخ الهجري.
   - محرك جلب بيانات غير متزامن (C# Async) لضمان ثبات النظام بنسبة 100% دون استهلاك موارد.

5. **ويدجت الموسيقى والوسائط (Music & Media Player):**
   - ربط مباشر بنظام الوسائط في ويندوز (SMTC) للتحكم في (Spotify, Anghami, YouTube, المتصفحات).
   - استخراج غلاف الألبوم بدقة عالية، وعرض اسم الفنان والتراك مع شريط التقدم والتحكم الكامل.

6. **التقويم الشهري التفاعلي (Interactive Calendar):**
   - استعراض الشهر الحالي مع تمييز اليوم النشط وإمكانية التنقل السريع بين الشهور.

7. **مؤقّت التركيز (Focus Pomodoro Timer):**
   - نظام إنتاجية 25 دقيقة عمل و 5 دقائق استراحة مع تنبيهات عند الانتهاء.

8. **الملاحظات السريعة (Quick Notes):**
   - مفكرة زجاجية عائمة تدعم الحفظ التلقائي الفوري (`notes.txt`)، وعداد الحروف، والتحريك السلس بالماوس مع قائمة كليك يمين متكاملة.

---

## 🎨 قسم المظهر والتخصيص (Appearance & Profiles)

تحكم كامل من خلال نافذة **Widgets Manager**:
- **5 ثيمات زجاجية:** Midnight (الافتراضي)، Slate، AMOLED، Amber، Cyan.
- **مستوى الشفافية (Opacity):** تحكم دقيق من 55% إلى 100%.
- **تحجيم الويدجتس (Scale):** خيارات تكبير وتصغير (85%, 100%, 115%).
- **أوضاع مسبقة (Profiles):**
  - **Work:** تفعيل أدوات الإنتاجية، الساعة، الطقس، النوتس، والـ HUD.
  - **Focus:** هدوء كامل، إبقاء الساعة ومؤقت التركيز فقط.
  - **Night:** واجهة ليلية هادئة مع الساعة والنوتس والطقس.
  - **Game:** الدوك فقط مع تحسين الأداء.
- **وضع توفير الطاقة (Low-Power Mode):** تقليل دورة تحديث الـ HUD للحفاظ على طاقة البطارية.
- **قفل وتحريك المواقع:** إمكانية سحب أي ويدجت وقفل مكانه على الشاشة.

---

## 💻 متطلبات التشغيل (Requirements)

- **نظام التشغيل:** Windows 10 أو Windows 11 (64-bit / ARM64).
- **البيئة البرمجية:** Windows PowerShell 5.1 (مثبت مسبقاً في ويندوز) + .NET Framework 4.7.2+.
- **الصلاحيات:** لا يتطلب صلاحيات مسؤول (Administrator).
- **الاتصال:** يعمل محلياً بالكامل دون الحاجة لاتصال بالإنترنت (عدا جلب الطقس).

---

## 🚀 التثبيت السريع (Quick Installation)

1. حمّل أحدث حزمة تثبيت من [GitHub Releases](../../releases).
2. فك ضغط الملف المضغوط `UNLOCK-DIGITAL-Widgets-v1.3.0.zip`.
3. اضغط مرتين على `Install.cmd`.
4. حدد خياراتك المفضلة واضغط **Install**.
5. ستعمل الويدجتس فوراً وستجد اختصارات التحكم في قائمة Start Menu تحت مجلد `UNLOCK DIGITAL`.

---

## 🛠️ البناء من المصدر (Building from Source)

لإنشاء حزمة التثبيت بنفسك:
```powershell
# استنساخ المستودع
git clone https://github.com/Es1amAshraf/unlock-digital-widgets.git
cd unlock-digital-widgets

# تشغيل سكربت البناء
powershell -ExecutionPolicy Bypass -File .\packaging\Build-Package.ps1
```
سيتم توليد ملف الحزمة المضغوطة تلقائياً داخل مجلد `dist/`.

---

## 📄 الترخيص (License)

هذا المشروع مرخص تحت رخصة [MIT License](LICENSE).
جميع الحقوق محفوظة لـ **UNLOCK DIGITAL**.
