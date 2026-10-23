// Все настройки оверлея в одном месте.
import QtQuick

QtObject {
    // ---------- Город и API ----------
    property string city: "Орёл"
    property real latitude: 52.9668
    property real longitude: 36.0625
    property int refreshMinutes: 10      // интервал опроса Open-Meteo/Yr (плюс 0..2 мин случайности)
    property int radarMinutes: 3         // опрос списка кадров радара RainViewer (кадр каждые 10 мин)
    property int radarMaxAgeMinutes: 25  // свежесть радарного кадра; старше — работаем по прогнозу

    // ---------- Поведение ----------
    property bool enabled: true          // общий выключатель (atmospheric toggle)
    property string layer: "top"         // "top" — под полноэкранными окнами,
                                         // "overlay" — всегда поверх всего
    property bool debugSquare: false     // этап 1: полупрозрачный красный квадрат + отладочный текст

    // ---------- Облачность ----------
    property bool dimCloudy: false       // затемнение при облачности (коды 2-3) —
                                          // УБРАНО по желанию: облачность больше
                                          // ничего не рисует, днём окно скрыто
    property real cloudyDimOpacity: 0.10 // на случай, если захотите вернуть

    // ---------- Ночь ----------
    property bool nightDim: false        // ГАСИТЬ экран ночью (правда меняет яркость!)
                                          // — по умолчанию выключено
    property real nightOpacity: 0.18     // сила затемнения, если nightDim: true
    property real nightTintOpacity: 0.06 // холодный оттенок ночью — яркость почти не трогает

    // ---------- Гроза ----------
    property real flashPeakOpacity: 0.20 // пиковая прозрачность вспышки

    // ---------- Туман ----------
    property real fogDensity: 2.5        // множитель количества облаков (2.5 ≈ в 2.5 раза гуще)
    property color fogColor: "#ccd9ea"    // серо-голубой: читается и на белом, и на тёмном
    property real fogSpeed: 12           // дрейф облаков, px/с (12 ≈ 2,5 мин на переход)
    property real fogOpacity: 0.45       // заметность тумана (0..1)
    // Второй сигнал тумана: видимость из Open-Meteo (часовой бин).
    // WMO 45/48 остаётся основным; видимость ловит «дымку» без туманного кода.
    property real fogVisibilityM: 1000   // видимость меньше — туман
    property real fogDenseVisibilityM: 300 // меньше — густой туман (облака плотнее и заметнее)

    // ---------- Метель ----------
    property real blizzardWind: 8        // снег + ветер сильнее — метель: плотнее, косее, быстрее

    // ---------- Дождь со снегом (переохлаждённый дождь, WMO 66/67) ----------
    property int sleetRainRate: 90       // капельная часть смеси
    property int sleetSnowRate: 12       // снежная часть смеси

    // ---------- Град (только с грозой, WMO 96/99) ----------
    property color hailColor: "#e3eefb"  // крупинки: холодный белый, в отличие от синеватого дождя
    property int hailRate: 240           // короткие быстрые крупинки поверх дождя

    // ---------- Радуга после дождя ----------
    property bool rainbowEnabled: true
    property int rainbowMinutes: 30      // сколько минут после дождя возможна дуга
    property real rainbowMaxSunAlt: 42   // солнце выше — радуга физически не видна
    property real rainbowOpacity: 0.40   // заметность дуги (0..1) — тихо, не заставка

    // ---------- Интенсивность: частиц в секунду ----------
    // Реальное число одновременных частиц ≈ rate * время жизни (с).
    // Дождь (жизнь ~1.2 с): 150 → ~180 капель на экране.
    property int drizzleRate: 60
    property int rainRate: 150
    property int heavyRainRate: 260
    property int thunderRate: 350         // гроза: ливень и гуще — плотный «стеной»
    property int snowRate: 18            // снег живёт ~16 с: 18 → ~290 хлопьев

    // ---------- Внешний вид капель и снежинок ----------
    property color rainColor: "#7fa9e6"   // дождь: синеватый, не белый
    property real rainOpacity: 0.30       // заметность капель (0..1, меньше — тише)
    property real rainLength: 20          // длина капли, px
    property color snowColor: "#e8f1ff"   // снежинки: чуть холодный белый
    property real snowOpacity: 0.42       // заметность снега
    property real snowSize: 11            // базовый размер хлопья, px
}
