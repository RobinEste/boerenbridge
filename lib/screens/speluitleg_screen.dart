import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

/// Scherm met speluitleg in drie varianten
class SpeluitlegScreen extends StatefulWidget {
  final String variant; // 'volledig', 'quickstart', of 'podcast'

  const SpeluitlegScreen({
    super.key,
    this.variant = 'volledig',
  });

  @override
  State<SpeluitlegScreen> createState() => _SpeluitlegScreenState();
}

class _SpeluitlegScreenState extends State<SpeluitlegScreen> {
  String _currentVariant = 'volledig';

  @override
  void initState() {
    super.initState();
    _currentVariant = widget.variant;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5EBD7),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: const Text('Speluitleg'),
        actions: [
          // Copy button voor podcast tekst
          if (_currentVariant == 'podcast')
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Kopieer naar klembord',
              onPressed: () => _copyToClipboard(context),
            ),
        ],
      ),
      body: Column(
        children: [
          // Tab buttons
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFF5EBD7),
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    label: 'Volledig',
                    icon: Icons.menu_book,
                    isSelected: _currentVariant == 'volledig',
                    onTap: () => setState(() => _currentVariant = 'volledig'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TabButton(
                    label: 'Quickstart',
                    icon: Icons.flash_on,
                    isSelected: _currentVariant == 'quickstart',
                    onTap: () => setState(() => _currentVariant = 'quickstart'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TabButton(
                    label: 'Podcast',
                    icon: Icons.podcasts,
                    isSelected: _currentVariant == 'podcast',
                    onTap: () => setState(() => _currentVariant = 'podcast'),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_currentVariant) {
      case 'quickstart':
        return const _QuickstartContent();
      case 'podcast':
        return const _PodcastContent();
      default:
        return const _VolledigContent();
    }
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    const podcastText = '''Boerenbridge Speluitleg - Podcast Script

Tagline: "Grote mond? Maak het waar (...of niet)"

Dit is een conversatief script over het kaartspel Boerenbridge. De toon moet toegankelijk, enthousiast en licht humoristisch zijn. Het is een gezelschapsspel dat al generaties lang gespeeld wordt met vrienden - meer kletsen dan kaarten, maar wel met die competitieve ondertoon van elkaar een beetje plagen.

KERNBOODSCHAP:
Boerenbridge is een kaartspel waar je niet probeert zoveel mogelijk te winnen, maar juist probeert PRECIES te voorspellen hoeveel slagen je gaat halen. Het is een spel van zelfkennis en inschatting.

DE BASICS:

Kaarten
Een standaard kaartspel heeft vier kleuren: Harten, Ruiten, Schoppen en Klaveren. Elke kleur heeft kaarten van 2 tot en met 10, plus Boer, Vrouw, Heer en Aas. De 2 is de laagste kaart, de Aas de hoogste.

Troef - De Superkleur
Elke ronde wordt één kleur aangewezen als "troef". Die kleur is dan oppermachtig. Zelfs de kleinste troefkaart verslaat de hoogste kaart van een andere kleur.

Hoe een slag werkt
1. De eerste speler legt een kaart neer en bepaalt daarmee de kleur
2. Iedereen moet dezelfde kleur bijleggen als ze die hebben
3. Heb je die kleur niet? Dan mag je troef spelen of iets anders afleggen
4. De hoogste kaart van de gevraagde kleur wint... tenzij er troef is gespeeld

HET UNIEKE: BIEDEN

Voordat je gaat spelen, kijk je naar je kaarten en voorspel je hoeveel slagen je gaat winnen. Dit heet "bieden".

Vuistregel voor beginners: tel je Azen plus je hoge troefkaarten. Dat is ongeveer je bod.

De Twist: Screw the Dealer
Het totaal van alle biedingen mag NIET gelijk zijn aan het aantal kaarten. De laatste bieder moet soms een bod doen dat eigenlijk niet past bij zijn kaarten.

SCOREN:

Goed geraden? Je krijgt 10 punten plus 2 punten per slag.
Fout geraden? Nul punten.

De kunst is niet om zoveel mogelijk te winnen, maar om PRECIES te halen wat je voorspelde.

DE RONDES: PIRAMIDE

Het aantal kaarten wisselt per ronde! Je speelt een piramide: van 1 kaart omhoog naar het maximum, dan weer terug naar 1.

Met 1 kaart: pure spanning! Met veel kaarten: strategie!

TIPS VOOR BEGINNERS:
1. Bied liever te laag dan te hoog
2. Azen winnen bijna altijd
3. Let op troef - één troefkaart kan alles veranderen
4. Nul bieden is lastig - je moet dan elke slag verliezen!

WAAROM DIT SPEL ZO VERSLAVEND IS:

Het mooiste moment? Wanneer je precies haalt wat je bood. Die voldoening als je "2" zei en exact twee slagen binnenhaalt - onbetaalbaar!

En het eerlijke is: geluk speelt mee, maar vaardigheid wint... tenminste, dat denkt Pascal.

Online kun je het spelen op lekkerkaarten.nl''';

    await Clipboard.setData(const ClipboardData(text: podcastText));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Podcast tekst gekopieerd naar klembord!'),
          backgroundColor: Color(0xFF8B7355),
        ),
      );
    }
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFF8B7355) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.white : const Color(0xFF8B7355),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF8B7355),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// VOLLEDIG CONTENT
// ============================================================================

class _VolledigContent extends StatelessWidget {
  const _VolledigContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitle('Boerenbridge'),
        const SizedBox(height: 4),
        const Text(
          'Grote mond? Maak het waar (...of niet)',
          style: TextStyle(
            fontSize: 16,
            fontStyle: FontStyle.italic,
            color: Color(0xFF8B7355),
          ),
        ),
        const SizedBox(height: 16),

        _buildSection(
          'Waarom dit spel zo verslavend is',
          'Stel je voor: je krijgt kaarten, je bekijkt ze, en dan moet je voorspellen hoeveel slagen je gaat winnen. Niet "ik hoop er drie" of "misschien vier" - nee, je zegt een getal en daar word je op afgerekend.\n\n'
              'Dat is Boerenbridge. Een spel waar je niet alleen tegen je tegenstanders speelt, maar vooral tegen jezelf. Kun jij je eigen hand goed inschatten?\n\n'
              'Het mooie is: soms win je juist door expres te verliezen. Als je voorspelt dat je nul slagen haalt en dat lukt, scoor je punten!',
        ),

        _buildSection(
          'De Basics: Kaarten en Hun Waarde',
          'Een standaard kaartspel heeft vier kleuren:\n'
              '♥ Harten (rood)\n'
              '♦ Ruiten (rood)\n'
              '♠ Schoppen (zwart)\n'
              '♣ Klaveren (zwart)\n\n'
              'Van laag naar hoog:\n'
              '2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → Boer → Vrouw → Heer → Aas\n\n'
              'Ezelsbruggetje: "Boer Vrouw Heer Aas" - alsof de boer onderaan de ladder staat.',
        ),

        _buildSection(
          'Wat is Troef? (De Superkleur)',
          'Elke ronde wordt één kleur uitgeroepen tot troef. Die kleur is dan de baas.\n\n'
              'Voorbeeld:\n'
              '• Troef is ♥ Harten\n'
              '• Iemand speelt de Aas van Schoppen (normaal de hoogste!)\n'
              '• Jij hebt geen Schoppen, maar wel een 2 van Harten\n'
              '• Die kleine ♥2 wint van de ♠Aas!\n\n'
              'Let op: Je mag alleen troef spelen als je de gevraagde kleur niet hebt.',
        ),

        _buildSection(
          'Hoe Werkt Een Slag?',
          '1. De eerste speler legt een kaart neer (bepaalt de kleur)\n'
              '2. Iedereen moet dezelfde kleur bijleggen als ze die hebben\n'
              '3. Heb je die kleur niet? Dan mag je troef spelen of iets anders afleggen\n'
              '4. De hoogste kaart van de gevraagde kleur wint\n'
              '5. ...tenzij er troef is gespeeld, dan wint de hoogste troef',
        ),

        _buildSection(
          'Het Bieden: Hier Wordt Het Spannend',
          'Voordat je gaat spelen, kijk je naar je kaarten en voorspel je hoeveel slagen je gaat winnen.\n\n'
              'Sterke kaarten (waarschijnlijk winnaars):\n'
              '• Azen (vooral van troef)\n'
              '• Heren en Vrouwen van troef\n'
              '• Hoge troefkaarten\n\n'
              'Vuistregel voor beginners:\n'
              'Tel je Azen + hoge troeven. Dat is ongeveer je bod.',
        ),

        _buildSection(
          'De Twist: "Screw the Dealer"',
          'Er is één gemene regel: het totaal van alle biedingen mag niet gelijk zijn aan het aantal kaarten.\n\n'
              'Waarom? Anders zou iedereen precies kunnen krijgen wat ze bieden, en dat is te makkelijk!\n\n'
              'De laatste bieder (de deler) moet soms een bod doen dat eigenlijk niet past bij zijn kaarten.',
        ),

        _buildSection(
          'Punten Scoren',
          'Goed geraden?\n'
              'Je krijgt 10 punten + 2 punten per slag die je hebt gewonnen.\n\n'
              '• 0 geboden, 0 gehaald → 10 punten\n'
              '• 1 geboden, 1 gehaald → 12 punten\n'
              '• 2 geboden, 2 gehaald → 14 punten\n'
              '• 3 geboden, 3 gehaald → 16 punten\n\n'
              'Fout geraden? 0 punten.\n\n'
              'De kunst is dus niet om zoveel mogelijk te winnen, maar om precies te halen wat je voorspelde.',
        ),

        _buildSection(
          'De Rondes: Van Klein naar Groot en Terug',
          'Het aantal kaarten wisselt per ronde!\n\n'
              '• Ronde 1: 1 kaart per speler\n'
              '• Ronde 2: 2 kaarten per speler\n'
              '• ... tot het maximum (bijv. 7 kaarten)\n'
              '• Dan weer terug naar beneden\n'
              '• Laatste ronde: 1 kaart per speler\n\n'
              'Je speelt dus een soort "piramide".',
        ),

        _buildSection(
          'Tips Voor Je Eerste Potje',
          '1. Begin voorzichtig - Bied liever te laag dan te hoog\n'
              '2. Azen zijn goud waard - Die winnen bijna altijd\n'
              '3. Let op troef - Eén troefkaart kan alles veranderen\n'
              '4. Nul bieden is lastig - Je moet dan elke slag verliezen!\n'
              '5. Kijk naar anderen - Wat hebben zij geboden?',
        ),

        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5EBD7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Het mooiste moment? Wanneer je precies haalt wat je bood. Die voldoening als je "2" zei en exact twee slagen binnenhaalt terwijl iedereen je probeerde te dwarsbomen - onbetaalbaar!\n\n'
            'Geluk speelt mee, maar vaardigheid wint... tenminste, dat denkt Pascal.',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Color(0xFF8B7355),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// QUICKSTART CONTENT
// ============================================================================

class _QuickstartContent extends StatelessWidget {
  const _QuickstartContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitle('Boerenbridge Quickstart'),
        const SizedBox(height: 8),
        const Text(
          'In 30 seconden klaar om te spelen!',
          style: TextStyle(
            fontSize: 16,
            color: Color(0xFF8B7355),
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 24),

        _buildQuickCard(
          'Doel',
          'Voorspel hoeveel slagen je wint, en haal dat precies.',
          Icons.flag,
        ),

        _buildQuickCard(
          'Kaarten',
          '2 is laagst, Aas is hoogst.\nBoer < Vrouw < Heer < Aas',
          Icons.style,
        ),

        _buildQuickCard(
          'Troef',
          'Eén kleur is de baas. Zelfs een troef-2 verslaat een Aas van een andere kleur.',
          Icons.star,
        ),

        _buildQuickCard(
          'Een slag',
          '1. Eerste speler legt een kaart (bepaalt de kleur)\n'
              '2. Iedereen moet dezelfde kleur bijleggen\n'
              '3. Hoogste kaart wint (troef > andere kleuren)',
          Icons.play_arrow,
        ),

        _buildQuickCard(
          'Bieden',
          'Vuistregel: tel je Azen + hoge troeven = je bod',
          Icons.campaign,
        ),

        _buildQuickCard(
          'Scoren',
          'Goed geraden: 10 + (2 × slagen) punten\nFout: 0 punten',
          Icons.scoreboard,
        ),

        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFE4B5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF8B7355)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lightbulb, color: Color(0xFF8B7355)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Het totaal van alle biedingen mag niet gelijk zijn aan het aantal kaarten (Screw the Dealer)',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF5D4E37),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Center(
          child: Text(
            'Succes! Na 2-3 rondes ben je een pro.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8B7355),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickCard(String title, String content, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5EBD7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF8B7355), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4E37),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6D5D4D),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PODCAST CONTENT
// ============================================================================

class _PodcastContent extends StatefulWidget {
  const _PodcastContent();

  @override
  State<_PodcastContent> createState() => _PodcastContentState();
}

class _PodcastContentState extends State<_PodcastContent> {
  late AudioPlayer _audioPlayer;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _audioPlayer.setAsset('assets/sounds/speluitleg_podcast.m4a');
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Kon audio niet laden';
      });
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitle('Podcast'),
        const SizedBox(height: 4),
        const Text(
          '"Grote mond? Maak het waar (...of niet)"',
          style: TextStyle(
            fontSize: 16,
            fontStyle: FontStyle.italic,
            color: Color(0xFF8B7355),
          ),
        ),
        const SizedBox(height: 24),

        // Audio Player
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B7355), Color(0xFF6D5D4D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.podcasts, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Boerenbridge Uitleg',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Gegenereerd met NotebookLM',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: Colors.white),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_error!, style: const TextStyle(color: Colors.white70)),
                )
              else ...[
                // Progress bar
                StreamBuilder<Duration?>(
                  stream: _audioPlayer.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final duration = _audioPlayer.duration ?? Duration.zero;
                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.white,
                            trackHeight: 4,
                          ),
                          child: Slider(
                            value: position.inMilliseconds.toDouble(),
                            max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                            onChanged: (value) {
                              _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),

                // Play/Pause controls
                StreamBuilder<PlayerState>(
                  stream: _audioPlayer.playerStateStream,
                  builder: (context, snapshot) {
                    final playerState = snapshot.data;
                    final playing = playerState?.playing ?? false;
                    final processingState = playerState?.processingState;

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Rewind 10s
                        IconButton(
                          icon: const Icon(Icons.replay_10, color: Colors.white, size: 32),
                          onPressed: () {
                            final newPosition = _audioPlayer.position - const Duration(seconds: 10);
                            _audioPlayer.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
                          },
                        ),
                        const SizedBox(width: 16),

                        // Play/Pause
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            iconSize: 40,
                            icon: Icon(
                              processingState == ProcessingState.loading ||
                                      processingState == ProcessingState.buffering
                                  ? Icons.hourglass_empty
                                  : playing
                                      ? Icons.pause
                                      : Icons.play_arrow,
                              color: const Color(0xFF8B7355),
                            ),
                            onPressed: () {
                              if (playing) {
                                _audioPlayer.pause();
                              } else {
                                _audioPlayer.play();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Forward 10s
                        IconButton(
                          icon: const Icon(Icons.forward_10, color: Colors.white, size: 32),
                          onPressed: () {
                            final duration = _audioPlayer.duration ?? Duration.zero;
                            final newPosition = _audioPlayer.position + const Duration(seconds: 10);
                            _audioPlayer.seek(newPosition > duration ? duration : newPosition);
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Script section
        Row(
          children: [
            const Icon(Icons.description, color: Color(0xFF8B7355)),
            const SizedBox(width: 8),
            Text(
              'Podcast Script',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF5D4E37).withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _buildPodcastSection(
          'Context voor de AI-host',
          'Dit is een conversatief script over het kaartspel Boerenbridge (ook wel "Oh Hell" genoemd). De toon moet toegankelijk, enthousiast en licht humoristisch zijn - alsof je het spel uitlegt aan een vriend die nog nooit een kaartspel heeft gespeeld. Het is een gezelschapsspel dat al generaties lang gespeeld wordt met vrienden - meer kletsen dan kaarten, maar wel met die competitieve ondertoon van elkaar een beetje plagen.\n\nTagline: "Grote mond? Maak het waar (...of niet)"',
        ),

        _buildPodcastSection(
          'Kernboodschap',
          'Boerenbridge is een kaartspel waar je niet probeert zoveel mogelijk te winnen, maar juist probeert PRECIES te voorspellen hoeveel slagen je gaat halen. Het is een spel van zelfkennis en inschatting.',
        ),

        _buildPodcastSection(
          'De Basics',
          'Een standaard kaartspel heeft vier kleuren: Harten, Ruiten, Schoppen en Klaveren. Elke kleur heeft kaarten van 2 tot en met 10, plus Boer, Vrouw, Heer en Aas. De 2 is de laagste kaart, de Aas de hoogste.\n\n'
              'Ezelsbruggetje: "Boer, Vrouw, Heer, Aas" - de boer staat onderaan de hiërarchie.',
        ),

        _buildPodcastSection(
          'Troef - De Superkleur',
          'Elke ronde wordt één kleur aangewezen als "troef". Die kleur is dan oppermachtig. Zelfs de kleinste troefkaart verslaat de hoogste kaart van een andere kleur.\n\n'
              'Voorbeeld: Stel Harten is troef. Iemand speelt de Aas van Schoppen - normaal de hoogste kaart! Maar jij hebt geen Schoppen, wel een piepkleine 2 van Harten. Die wint!',
        ),

        _buildPodcastSection(
          'Hoe een slag werkt',
          '1. De eerste speler legt een kaart neer en bepaalt daarmee de kleur\n'
              '2. Iedereen moet dezelfde kleur bijleggen als ze die hebben\n'
              '3. Heb je die kleur niet? Dan mag je troef spelen of iets anders afleggen\n'
              '4. De hoogste kaart van de gevraagde kleur wint... tenzij er troef is gespeeld',
        ),

        _buildPodcastSection(
          'Het Unieke: Bieden',
          'Voordat je gaat spelen, kijk je naar je kaarten en voorspel je hoeveel slagen je gaat winnen. Dit heet "bieden".\n\n'
              'Vuistregel voor beginners: tel je Azen plus je hoge troefkaarten. Dat is ongeveer je bod.\n\n'
              'De Twist - Screw the Dealer: Het totaal van alle biedingen mag NIET gelijk zijn aan het aantal kaarten. De laatste bieder moet soms een bod doen dat eigenlijk niet past bij zijn kaarten.',
        ),

        _buildPodcastSection(
          'Scoren',
          'Goed geraden? Je krijgt 10 punten plus 2 punten per slag.\n'
              'Fout geraden? Nul punten.\n\n'
              'De kunst is niet om zoveel mogelijk te winnen, maar om PRECIES te halen wat je voorspelde.',
        ),

        _buildPodcastSection(
          'De Rondes: Piramide',
          'Het aantal kaarten wisselt per ronde! Je speelt een piramide: van 1 kaart omhoog naar het maximum, dan weer terug naar 1.\n\n'
              'Met 1 kaart: pure spanning!\nMet veel kaarten: hier komt strategie!',
        ),

        _buildPodcastSection(
          'Tips voor beginners',
          '1. Bied liever te laag dan te hoog\n'
              '2. Azen winnen bijna altijd\n'
              '3. Let op troef - één troefkaart kan alles veranderen\n'
              '4. Nul bieden is lastig - je moet dan elke slag verliezen!',
        ),

        _buildPodcastSection(
          'Afsluiting',
          'Het mooiste moment? Wanneer je precies haalt wat je bood. Die voldoening als je "2" zei en exact twee slagen binnenhaalt - onbetaalbaar!\n\n'
              'En het eerlijke is: geluk speelt mee, maar vaardigheid wint... tenminste, dat denkt Pascal.\n\n'
              'Online kun je het spelen op lekkerkaarten.nl',
        ),
      ],
    );
  }
}

// ============================================================================
// SHARED WIDGETS
// ============================================================================

Widget _buildPodcastSection(String title, String content) {
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE0E0E0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF8B7355),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF424242),
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

Widget _buildTitle(String text) {
  return Text(
    text,
    style: const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: Color(0xFF5D4E37),
    ),
  );
}

Widget _buildSection(String title, String content) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 24),
      Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Color(0xFF8B7355),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        content,
        style: const TextStyle(
          fontSize: 15,
          color: Color(0xFF5D4E37),
          height: 1.5,
        ),
      ),
    ],
  );
}
