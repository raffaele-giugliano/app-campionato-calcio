import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
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

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchAndParseData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  DateTime? _parseData(String dataStr) {
    try {
      final cleanStr = dataStr.trim().replaceAll('/', '-');
      final parts = cleanStr.split('-');
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

      // 1. Download con proxy e timeout di 3 secondi per evitare blocchi
      final proxyUrl = 'https://corsproxy.io/?' + Uri.encodeComponent(_csvUrl);
      try {
        final res = await http.get(Uri.parse(proxyUrl)).timeout(
              const Duration(seconds: 3),
            );
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          csvRawContent = res.body;
        }
      } catch (_) {}

      // 2. Fallback chiamata diretta
      if (csvRawContent == null || csvRawContent.isEmpty) {
        final res = await http.get(Uri.parse(_csvUrl)).timeout(
              const Duration(seconds: 4),
            );
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

          final oggi = DateTime.now();
          final oggiSenzaOra = DateTime(oggi.year, oggi.month, oggi.day);
          int indiceEvidenziato = -1;

          for (int i = 0; i < tempRighe.length; i++) {
            final riga = tempRighe[i];
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
                  break;
                }
              }
            }
          }

          setState(() {
            _righePartite = tempRighe;
            _indiceProssimaPartita = indiceEvidenziato;
            _isLoading = false;
          });

          // Scroll basato sull'offset stimato
          if (_indiceProssimaPartita > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToProssimaPartitaOffset();
            });
          }
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

  void _scrollToProssimaPartitaOffset() {
    if (_indiceProssimaPartita > 0 && _scrollController.hasClients) {
      // Calcolo stimato dell'altezza di ciascuna card + margini
      const double altezzaStimataCard = 150.0;
      final double targetOffset = _indiceProssimaPartita * altezzaStimataCard;

      final double maxScroll = _scrollController.position.maxScrollExtent;
      final double finalOffset =
          targetOffset > maxScroll ? maxScroll : targetOffset;

      _scrollController.animateTo(
        finalOffset,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
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
        title: const Text('CSRB U14 Squadra B - Campionato 2026/27'),
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
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _righePartite.length,
                  itemBuilder: (context, index) {
                    final riga = _righePartite[index];
                    final isEvidenziata = (index == _indiceProssimaPartita);

                    final campiDaColonnaB =
                        riga.length > 1 ? riga.sublist(1) : riga;

                    List<CampoDato> campiPrimaPagina = [];
                    for (var campo in campiDaColonnaB) {
                      campiPrimaPagina.add(campo);
                      if (campo.intestazione.trim().toLowerCase() == 'note') {
                        break;
                      }
                    }

                    final campiDaMostrare = campiPrimaPagina
                        .where((c) => c.valore.isNotEmpty)
                        .toList();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16.0),
                      decoration: BoxDecoration(
                        color: isEvidenziata
                            ? const Color(0xFFEBF3FF)
                            : const Color(0xFFF2F4F7),
                        borderRadius: BorderRadius.circular(16.0),
                        border: Border.all(
                          color: isEvidenziata
                              ? const Color(0xFF2563EB)
                              : Colors.transparent,
                          width: 2.0,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16.0),
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
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isEvidenziata) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10.0, vertical: 4.0),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1D4ED8),
                                    borderRadius: BorderRadius.circular(6.0),
                                  ),
                                  child: const Text(
                                    'PROSSIMA PARTITA',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12.0),
                              ],
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: campiDaMostrare.map((item) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 4.0),
                                          child: RichText(
                                            text: TextSpan(
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey.shade900,
                                              ),
                                              children: [
                                                TextSpan(
                                                  text:
                                                      '${item.intestazione} ',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                TextSpan(text: item.valore),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.grey.shade500,
                                    size: 24,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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

  Future<void> _apriGoogleMaps(String indirizzo) async {
    final query = Uri.encodeComponent(indirizzo);
    final url =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  bool _isCampoIndirizzo(String header) {
    final cleanHeader = header.trim().toLowerCase();
    return cleanHeader.contains('indirizzo') || cleanHeader.contains('campo');
  }

  @override
  Widget build(BuildContext context) {
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
            final isIndirizzo = _isCampoIndirizzo(item.intestazione);
            final haValore =
                item.valore.trim().isNotEmpty && item.valore != '-';

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
                    item.valore.isEmpty
                        ? '-'
                        : item.valore.replaceAll(', ', '\n'),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  if (isIndirizzo && haValore) ...[
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => _apriGoogleMaps(item.valore),
                      icon: const Icon(Icons.map),
                      label: const Text('Apri Google Maps'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}