<?php
// Разрешаем CORS
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header("Access-Control-Allow-Credentials: true");

header('Content-Type: application/plain'); 

// Проверяем, есть ли параметр url
if (!isset($_GET['url']) || empty($_GET['url'])) {
    echo json_encode(['error' => 'URL is required']);
    exit;
}

// Формируем URL, не добавляя параметры, если их нет
$url = $_GET['url'];
if (isset($_GET['no_404'])) {
    $url .= '&no_404=' . urlencode($_GET['no_404']);
}
if (isset($_GET['referer'])) {
    $url .= '&referer=' . urlencode($_GET['referer']);
}
if (!str_contains($url, "uma.media"))
{
    echo "Error";
    die;
}
// Если это preflight-запрос (OPTIONS), просто выходим
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Инициализируем cURL
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $url);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true); // Разрешаем редиректы
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false); // Отключаем проверку SSL
curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'GET');

// Добавляем User-Agent (иногда нужен для работы API)
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
]);

// Выполняем запрос
$response = curl_exec($ch);

// Проверяем на ошибки
if ($response === false) {
    echo json_encode(['error' => 'cURL error: ' . curl_error($ch)]);
} else {
    echo $response; // Отдаем ответ клиента
}

// Закрываем соединение
curl_close($ch);
?>
