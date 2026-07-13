import 'package:flutter/material.dart';
import 'app/app.dart';
import 'core/network/http_client.dart';
import 'core/store/user_store.dart';

void main() {
  HttpClient.init(
    baseUrl: 'http://127.0.0.1:8080',
    tokenProvider: TokenProvider(getToken: UserStore.provideToken),
  );
  runApp(const App());
}
