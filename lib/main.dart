import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const CampionatoApp());
}

class CampionatoApp extends StatelessWidget {
  const CampionatoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calcio CSRB 2026-2027',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ListaPartiteScreen(),
    );
  }
}

class CampoDato {
  final String intestazione;
  final String valore;

  CampoDato({required this.intestazione, required this.valore});
}

class ListaPartiteScreen extends StatefulWidget {
  const ListaPartiteScreen({super.key});

  @override
  State<ListaPartiteScreen> createState() => _ListaPartiteScreenState();
}

class _ListaPartiteScreenState extends State<ListaPartiteScreen> {
  final String _csvUrl =
      'https://docs.google.com/spreadsheets/d/e/2PACX-1vTA-oDFCDZIShzqfWXWlxsl1UZjQnlJrR3nmg6c82n9jBFKv5VHb3_RDLUQCAxQpZpJZDki4vVGPdbq/pub?gid=0&single=true&output=csv';

  bool _isLoading = true;
  String? _errorMessage;
  List<List<CampoDato>> _righePartite = [];
  int _indiceProssimaPartita = -1;

  @override
  void initState() {
    super.initState();
    _fetchAndParseData();
  }

  // Converte la stringa data 'gg-mm-aaaa' in DateTime per il confronto
  DateTime? _parseData(String dataStr) {
    try {
      final parts = dataStr.trim().split('-');
      if (parts.length == 3) {
        final giorno = int.parse(parts[0]);
        final mese = int.parse(parts[1]);
        final anno = int.parse(parts[2]);
        return DateTime(anno, mese, giorno);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchAndParseData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? csvRawContent;

      // 1. Prova download tramite corsproxy.io per superare restrizioni CORS
      final proxyUrl = 'https://corsproxy.io/?' + Uri.encodeComponent(_csvUrl);
      try {
        final res = await http.get(Uri.parse(proxyUrl));
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          csvRawContent = res.body;
        }
      } catch (_) {}

      // 2. Fallback chiamata diretta
      if (csvRawContent == null || csvRawContent.isEmpty) {
        final res = await http.get(Uri.parse(_csvUrl));
        if (res.statusCode == 200) {
          csvRawContent = res.body;
        }
      }

      if (csvRawContent != null && csvRawContent.isNotEmpty) {
        List<List<String>> righeCsv = _parseCsv(csvRawContent);

        if (righeCsv.isNotEmpty) {
          List<String> headers = righeCsv.first;
          List<List<CampoDato>> tempRighe = [];

          for (int r = 1; r < righeCsv.length; r++) {
            List<String> riga = righeCsv[r];
            List<CampoDato> campiRiga = [];

            for (int c = 0; c < headers.length; c++) {
              String header = headers[c].trim();
              String val = c < riga.length ? riga[c].trim() : '';

              if (header.isNotEmpty) {
                campiRiga.add(CampoDato(
                  intestazione: header,
                  valore: val,
                ));
              }
            }

            if (campiRiga.any((c) => c.valore.isNotEmpty)) {
              tempRighe.add(campiRiga);
            }
          }

          // Calcolo della prima riga con giorno >= data odierna
          final oggi = DateTime.now();
          final oggiSenzaOra = DateTime(oggi.year, oggi.month, oggi.day);
          int indiceEvidenziato = -1;

          for (int i = 0; i < tempRighe.length; i++) {
            final riga = tempRighe[i];
            // Cerca il campo con intestazione 'giorno'
            final campoGiorno = riga.firstWhere(
              (c) => c.intestazione.trim().toLowerCase() == 'giorno',
              orElse: () => CampoDato(intestazione: '', valore: ''),
            );

            if (campoGiorno.valore.isNotEmpty) {
              final dataPartita = _parseData(campoGiorno.valore);
              if (dataPartita != null) {
                if (dataPartita.isAfter(oggiSenzaOra) ||
                    dataPartita.isAtSameMomentAs(oggiSenzaOra)) {
                  indiceEvidenziato = i;
                  break; // Trovata la prima partita >= oggi
                }
              }
            }
          }

          setState(() {
            _righePartite = tempRighe;
            _indiceProssimaPartita = indiceEvidenziato;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'Nessun dato trovato nel file CSV.';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Impossibile scaricare i dati da Google Sheets.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore durante la lettura dei dati: $e';
        _isLoading = false;
      });
    }
  }

  List<List<String>> _parseCsv(String responseBody) {
    List<List<String>> result = [];
    List<String> lines = responseBody.split(RegExp(r'\r\n|\n|\r'));

    for (var line in lines) {
      if (line.trim().isEmpty) continue;

      List<String> row = [];
      StringBuffer sb = StringBuffer();
      bool inQuotes = false;

      for (int i = 0; i < line.length; i++) {
        String char = line[i];
        if (char == '"') {
          inQuotes = !inQuotes;
        } else if (char == ',' && !inQuotes) {
          row.add(sb.toString());
          sb.clear();
        } else {
          sb.write(char);
        }
      }
      row.add(sb.toString());
      result.add(row);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partite CSRB'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAndParseData,
            tooltip: 'Aggiorna',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchAndParseData,
                        child: const Text('Riprova'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _righePartite.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final riga = _righePartite[index];
                    final isEvidenziata = (index == _indiceProssimaPartita);

                    // Escludiamo la Colonna A (indice 0)
                    final campiDaColonnaB =
                        riga.length > 1 ? riga.sublist(1) : riga;

                    // Filtra solo i campi fino alla colonna 'Note' (inclusa) per la schermata principale
                    List<CampoDato> campiPrimaPagina = [];
                    for (var campo in campiDaColonnaB) {
                      campiPrimaPagina.add(campo);
                      if (campo.intestazione.trim().toLowerCase() == 'note') {
                        break;
                      }
                    }

                    // Prende solo quelli con valore non vuoto
                    final campiDaMostrare = campiPrimaPagina
                        .where((c) => c.valore.isNotEmpty)
                        .toList();

                    return Container(
                      color: isEvidenziata ? Colors.cyan.shade100 : Colors.transparent,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        title: Wrap(
                          spacing: 12.0,
                          runSpacing: 6.0,
                          children: campiDaMostrare.map((item) {
                            return RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade900,
                                ),
                                children: [
                                  TextSpan(
                                    text: '${item.intestazione} ',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextSpan(text: item.valore),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DettaglioPartitaScreen(
                                rigaCompleta: riga,
                                indexRiga: index + 1,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

class DettaglioPartitaScreen extends StatelessWidget {
  final List<CampoDato> rigaCompleta;
  final int indexRiga;

  const DettaglioPartitaScreen({
    super.key,
    required this.rigaCompleta,
    required this.indexRiga,
  });

  @override
  Widget build(BuildContext context) {
    // Nella pagina di dettaglio mostra TUTTI i campi dalla Colonna B in poi
    final campiDettaglio =
        rigaCompleta.length > 1 ? rigaCompleta.sublist(1) : rigaCompleta;

    return Scaffold(
      appBar: AppBar(
        title: Text('Dettaglio Partita $indexRiga'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: campiDettaglio.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.intestazione,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.valore.isEmpty ? '-' : item.valore,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}