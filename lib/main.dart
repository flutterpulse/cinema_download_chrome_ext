import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as htmlParser;
import 'package:chrome_extension/tabs.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Dio dio = Dio();
  static const String proxy = "http://f1084800.xsph.ru/proxy.php?url=";
  late String _currentUrl; // текущий url
  List<String> _messages = []; // сообщения для пользователя, включая служебные
  bool _fetchLastEpisode = false; // только последний эпизод
  bool _fetchLastSeason = false; // только последний сезон
  // наличие кнопок: null - сайт не поддерживается, false - не найдены ссылки (не запускался поиск), true - найдены ссылки
  bool? _enabled;

  @override
  void initState() {
    _getCurrentUrl();
    super.initState();
  }

  Future<void> _getCurrentUrl() async {
    try {
      var tabs = await chrome.tabs.query(QueryInfo(
        active: true,
        currentWindow: true,
      ));
      setState(() {
        _currentUrl = "https://" + Uri.parse(tabs.first.url!).host;
        if (_currentUrl.contains(".friday.ru")) _enabled = false;
      });
    } catch (e) {
      setState(() {
        _enabled = false;
        _currentUrl = "https://chiefbattle.friday.ru";
      });
    }
  }

  void _addMessage(String message) {
    setState(() {
      _messages.add(message);
    });
  }

  void _copyAllLinks() {
    // Собираем все строки с "yt-dlp"
    String allLinks =
        _messages.where((message) => message.contains("yt-dlp")).join("\n");

    // Копируем их в буфер обмена
    Clipboard.setData(ClipboardData(text: allLinks));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Все ссылки скопированы!")),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Скопировано!")),
    );
  }

  Future<void> _fetchVideoLinks(List<String> episodeLinks) async {
    if (_fetchLastEpisode) {
      episodeLinks = [episodeLinks.first];
    }
    for (String episode in episodeLinks) {
      _addMessage('🔍 Обрабатываем: $episode');

      try {
        // 🔹 1. Получаем HTML страницы эпизода
        final response = await dio.get(episode);
        var document = htmlParser.parse(response.data);

        // 🔹 2. Ищем `iframe`
        var iframeElement = document.querySelector('iframe');
        if (iframeElement == null || iframeElement.attributes['src'] == null) {
          _addMessage('❌ Не найден iframe на странице.');
          continue;
        }

        String iframeSrc = iframeElement.attributes['src']!;
        String videoId = iframeSrc.substring(
            iframeSrc.lastIndexOf('/') + 1, iframeSrc.lastIndexOf('?'));

        // 🔹 3. Формируем API-запрос к uma.media
        String apiUrl = proxy +
            'https://uma.media/api/play/options/$videoId/?format=json&no_404=true&referer=$episode';
        final apiResponse = await dio.get(apiUrl);

        // Проверяем тип данных в ответе
        var responseData = apiResponse.data;

        if (responseData is String) {
          responseData =
              jsonDecode(responseData); // Принудительно декодируем JSON
        }
        Map<String, dynamic> jsonData = responseData;
        if (!jsonData.containsKey("video_balancer") ||
            !jsonData["video_balancer"].containsKey("default")) {
          _addMessage('❌ Ошибка: Невалидный JSON.');
          continue;
        }
        String playlistUrl = proxy + jsonData["video_balancer"]["default"];
        // 🔹 4. Получаем список потоков M3U8
        final playlistResponse = await dio.get(playlistUrl);
        List<String> lines = LineSplitter().convert(playlistResponse.data);
        // 🔹 5. Ищем ссылки и разрешения
        List<int> resolutions = [];
        List<String> streamUrls = [];

        for (int i = 0; i < lines.length; i++) {
          if (lines[i].contains("RESOLUTION=")) {
            String res = lines[i].split("RESOLUTION=")[1].split(",")[0];
            List<String> size = res.split('x');
            int resValue = int.parse(size[0]) * int.parse(size[1]);
            resolutions.add(resValue);
            streamUrls.add(lines[i + 1]); // Следующая строка - URL
          }
        }
        // 🔹 6. Выбираем лучшее качество
        if (resolutions.isNotEmpty) {
          int maxIndex =
              resolutions.indexOf(resolutions.reduce((a, b) => a > b ? a : b));
          String bestUrl = streamUrls[maxIndex];

          String filename =
              episode.replaceAll(RegExp(r'.*/videos/'), '') + '.mp4';
          String ytDlpCmd = 'yt-dlp -o "$filename" "$bestUrl"';
          _addMessage(ytDlpCmd);
          _enabled = true;
        } else {
          _addMessage('❌ Не удалось найти ссылки на поток.');
        }
      } catch (e) {
        _addMessage('❌ Ошибка обработки: $e');
      }
    }
  }

  Future<void> _getVideoLinks() async {
    _messages = [];
    _addMessage('🔄 Получаем ссылки на все сезоны...');
    try {
      final response = await dio.get(_currentUrl);
      var document = htmlParser.parse(response.data);
      List<String> seasonLinks = [];
      List<String> seasonNames = [];

      for (var link in document.querySelectorAll('a')) {
        String href = link.attributes['href'] ?? '';
        if (href.contains('#seasons') && link.text.contains('Сезон')) {
          if (!seasonLinks
              .contains(Uri.parse(_currentUrl).resolve(href).toString())) {
            seasonLinks.add(Uri.parse(_currentUrl).resolve(href).toString());
            seasonNames.add(link.text);
            if (_fetchLastSeason || _fetchLastEpisode) break;
          }
        }
      }

      if (seasonLinks.isEmpty) {
        seasonLinks.add('$_currentUrl/videos/s1#seasons');
        seasonNames.add('Сезон 1');
      }

      _addMessage('✅ Найдено сезонов: ${seasonLinks.length}');

      List<String> episodeLinks = [];
      for (int season = 0; season < seasonLinks.length; season++) {
        final seasonResponse = await dio.get(seasonLinks[season]);
        var seasonDocument = htmlParser.parse(seasonResponse.data);

        for (var link in seasonDocument.querySelectorAll('div')) {
          String? dataLoadMoreFilter = link.attributes['data-load-more-filter'];
          if (dataLoadMoreFilter != null &&
              dataLoadMoreFilter.contains('folder')) {
            Map<String, dynamic> data = jsonDecode(dataLoadMoreFilter);
            int page = 0;
            int count = 0;

            while (true) {
              final postResponse = await dio.post(
                '$_currentUrl/api/show/season-video',
                data: FormData.fromMap({
                  'action': 'get_new',
                  'data[page]': page.toString(),
                  'data[filter][name]': data["name"],
                  'data[filter][folder]': data["folder"],
                  'data[filter][is_num]': 'false',
                  'data[filter][season]': data["season"].toString(),
                  'data[filter][single]': 'false',
                  'data[filter][hasTgb]': 'false'
                }),
              );

              // Проверяем, является ли postResponse.data строкой
              dynamic responseData = postResponse.data;
              if (responseData is String) {
                try {
                  responseData = jsonDecode(responseData);
                } catch (e) {
                  _addMessage('❌ Ошибка декодирования JSON: $e');
                  return;
                }
              }

              // Убеждаемся, что данные корректные
              if (responseData is! Map<String, dynamic> ||
                  !responseData.containsKey("data")) {
                _addMessage('❌ Ошибка: Неверный формат ответа от сервера.');
                return;
              }

              // Теперь безопасно работаем с responseData
              var resultsDocument =
                  htmlParser.parse(responseData["data"]['results']);

              for (var link in resultsDocument.querySelectorAll('a')) {
                if (link.classes.contains('_big') &&
                    link.attributes['href'] != 'None') {
                  String episodeLink = link.attributes['href']!;
                  episodeLinks.add(
                      Uri.parse(_currentUrl).resolve(episodeLink).toString());
                  count++;
                }
              }

              if (!responseData["data"]["haveMorePages"]) {
                break;
              }
              page++;
            }

            _addMessage('📺 В ${seasonNames[season]} найдено серий: $count');
          }
        }
      }

      _addMessage('🎉 Всего найдено эпизодов: ${episodeLinks.length}');
      await _fetchVideoLinks(episodeLinks);
    } catch (e) {
      _addMessage('❌ Ошибка: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _enabled == null
              ? Text("Не поддерживается для данного сайта")
              : Expanded(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: (){
                          setState(() {
                            _fetchLastEpisode = !_fetchLastEpisode;
                          });
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _fetchLastEpisode,
                              onChanged: (bool? value) {
                                setState(() {
                                  _fetchLastEpisode =_fetchLastEpisode = !_fetchLastEpisode;
                                });
                              },
                            ),
                            const Text("Получить ссылку на последний эпизод"),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: (){
                          setState(() {
                            _fetchLastSeason = !_fetchLastSeason;
                          });
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _fetchLastSeason,
                              onChanged: (bool? value) {
                                setState(() {
                                  _fetchLastSeason = !_fetchLastSeason;
                                });
                              },
                            ),
                            const Text(
                                "Получить ссылки только на последний сезон"),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _getVideoLinks,
                        child: Text("🔍 Найти видео на " + _currentUrl),
                      ),
                      if (_enabled == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 10.0),
                          child: ElevatedButton(
                            onPressed: _copyAllLinks,
                            child: const Text("Скопировать все ссылки"),
                          ),
                        ),
                      Expanded(
                          child: ListView.builder(
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          String message = _messages[index];
                          return ListTile(
                            title: Text(message),
                            trailing: message.startsWith('yt-dlp')
                                ? IconButton(
                                    icon: const Icon(Icons.copy),
                                    onPressed: () => _copyToClipboard(message),
                                  )
                                : null,
                          );
                        },
                      )),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}
