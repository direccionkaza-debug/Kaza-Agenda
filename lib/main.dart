import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const MiAgendaApp());

// Paleta de colores oficial de tu marca "Kaza"
class KazaColores {
  static const Color azulMarino = Color(0xFF00008B); // Azul marino profundo
  static const Color naranja = Color(0xFFFF5500); // Naranja vibrante
  static const Color blanco = Colors.white;
}

class MiAgendaApp extends StatelessWidget {
  const MiAgendaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: KazaColores.azulMarino,
          primary: KazaColores.azulMarino,
          secondary: KazaColores.naranja,
        ),
        useMaterial3: true,
      ),
      home: const AgendaVentanaUnica(),
    );
  }
}

class AgendaVentanaUnica extends StatefulWidget {
  const AgendaVentanaUnica({super.key});

  @override
  State<AgendaVentanaUnica> createState() => _AgendaVentanaUnicaState();
}

class _AgendaVentanaUnicaState extends State<AgendaVentanaUnica> {
  // Controladores de texto para los campos en pantalla
  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _telefonoCtrl = TextEditingController();
  final TextEditingController _ubicacionCtrl = TextEditingController();

  DateTime? _fechaSeleccionada;
  TimeOfDay? _horaSeleccionada;

  // --- NUEVO: Control del Combobox (Tipo de Cita) ---
  final List<String> _tiposDeCita = [
    'Visita para Renta',
    'Visita para Venta',
    'Firma de Contrato',
    'Visita con Propietario',
  ];
  String? _tipoCitaSeleccionado; // Almacenará la opción elegida por el usuario

  // Base de datos local en memoria - INICIA COMPLETAMENTE VACÍA
  final List<Map<String, String>> _citasGuardadas = [];

  // Rango de horas en las que trabajas (Formato 24 Horas)
  final List<int> _horasLaborales = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18];

  // Selector de fecha
  Future<void> _elegirFecha() async {
    final DateTime? fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (fecha != null) {
      setState(() => _fechaSeleccionada = fecha);
    }
  }

  // Selector de reloj en formato 24 horas
  Future<void> _elegirHora() async {
    final TimeOfDay? hora = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (hora != null) {
      setState(() => _horaSeleccionada = hora);
    }
  }

  // Calcula qué horas de tu jornada de trabajo están libres en la fecha seleccionada
  List<int> _obtenerHorasDisponibles(DateTime fecha) {
    String prefijoFecha =
        "${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}";

    List<int> horasOcupadas = [];
    for (var cita in _citasGuardadas) {
      if (cita['fechaHora']!.startsWith(prefijoFecha)) {
        String horaStr = cita['fechaHora']!.split(' ')[1].split(':')[0];
        horasOcupadas.add(int.parse(horaStr));
      }
    }

    return _horasLaborales.where((h) => !horasOcupadas.contains(h)).toList();
  }

  // Valida los datos, el tipo de cita y el horario antes de mandar a Google Calendar
  Future<void> _procesarCita() async {
    if (_nombreCtrl.text.isEmpty ||
        _ubicacionCtrl.text.isEmpty ||
        _fechaSeleccionada == null ||
        _horaSeleccionada == null ||
        _tipoCitaSeleccionado == null) {
      _mostrarMensaje(
          '⚠️ Por favor completa Nombre, Tipo de Cita, Ubicación, Fecha y Hora.',
          Colors.redAccent);
      return;
    }

    String fechaStr =
        "${_fechaSeleccionada!.year}-${_fechaSeleccionada!.month.toString().padLeft(2, '0')}-${_fechaSeleccionada!.day.toString().padLeft(2, '0')}";
    String horaStr =
        "${_horaSeleccionada!.hour.toString().padLeft(2, '0')}:${_horaSeleccionada!.minute.toString().padLeft(2, '0')}";
    String fechaHoraIntento = "$fechaStr $horaStr";

    // ¿Ya tienes una cita agendada a esa misma hora?
    bool estaOcupado =
        _citasGuardadas.any((cita) => cita['fechaHora'] == fechaHoraIntento);

    if (estaOcupado) {
      List<int> libres = _obtenerHorasDisponibles(_fechaSeleccionada!);
      String libresTexto = libres.isEmpty
          ? "No hay horarios disponibles hoy."
          : libres.map((h) => "$h:00").join(', ');

      _mostrarDialogoConflicto(libresTexto);
      return;
    }

    // Si está libre, la guardamos en el registro interno de la pantalla
    setState(() {
      _citasGuardadas.add({
        'fechaHora': fechaHoraIntento,
        'nombre': _nombreCtrl.text,
        'tipo': _tipoCitaSeleccionado!,
        'ubicacion': _ubicacionCtrl.text,
        'telefono': _telefonoCtrl.text,
      });
    });

    // Abrimos Google Calendar para agendar el evento
    await _abrirEnGoogleCalendarReal(fechaStr, horaStr);
  }

  // Configura el enlace para abrir Google Calendar para AGENDAR
  Future<void> _abrirEnGoogleCalendarReal(
      String fechaStr, String horaStr) async {
    final horaInicioObj = DateTime(
      _fechaSeleccionada!.year,
      _fechaSeleccionada!.month,
      _fechaSeleccionada!.day,
      _horaSeleccionada!.hour,
      _horaSeleccionada!.minute,
    );
    final horaFinObj = horaInicioObj.add(const Duration(hours: 1));

    final formatoInicio = horaInicioObj
            .toUtc()
            .toIso8601String()
            .replaceAll('-', '')
            .replaceAll(':', '')
            .split('.')
            .first +
        'Z';
    final formatoFin = horaFinObj
            .toUtc()
            .toIso8601String()
            .replaceAll('-', '')
            .replaceAll(':', '')
            .split('.')
            .first +
        'Z';

    final tituloCompleto = '${_nombreCtrl.text} ($_tipoCitaSeleccionado)';
    final titulo = Uri.encodeComponent(tituloCompleto);
    final ubicacion = Uri.encodeComponent(_ubicacionCtrl.text);
    final descripcion = Uri.encodeComponent('🏡 Cita de Servicios Kaza\n\n'
        '• Cliente: ${_nombreCtrl.text}\n'
        '• Motivo: $_tipoCitaSeleccionado\n'
        '• Teléfono: ${_telefonoCtrl.text}\n'
        '• Dirección de la cita: ${_ubicacionCtrl.text}');

    final urlGoogleCalendar = 'https://calendar.google.com/calendar/render'
        '?action=TEMPLATE'
        '&text=$titulo'
        '&dates=$formatoInicio/$formatoFin'
        '&details=$descripcion'
        '&location=$ubicacion';

    final uri = Uri.parse(urlGoogleCalendar);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      _mostrarMensaje(
          '✅ Cita registrada. Confirma presionando "Guardar" en tu calendario.',
          Colors.green);
      _limpiarFormulario();
    } else {
      _mostrarMensaje(
          '❌ No se pudo redirigir a Google Calendar.', Colors.redAccent);
    }
  }

  // Redirige a Google Calendar al cancelar
  Future<void> _redirigirParaBorrar(String fechaHoraStr) async {
    try {
      List<String> partes = fechaHoraStr.split(' ');
      String fechaSola = partes[0].replaceAll('-', '');

      final urlCalendarDia =
          'https://calendar.google.com/calendar/render?action=MAIN&date=$fechaSola';
      final uri = Uri.parse(urlCalendarDia);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      final uri = Uri.parse('https://calendar.google.com/');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  // Alerta visual de choque de horarios
  void _mostrarDialogoConflicto(String horasLibres) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: KazaColores.naranja),
            SizedBox(width: 10),
            Text('¡Horario Ocupado!'),
          ],
        ),
        content: Text(
          'Ya tienes programada una cita a esa hora.\n\n'
          'Horas que tienes libres para este día:\n$horasLibres',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido',
                style: TextStyle(
                    color: KazaColores.azulMarino,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Pregunta de confirmación para eliminar la cita y liberar el horario
  void _confirmarCancelacion(
      int index, String nombreCliente, String fechaHora) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('¿Eliminar Cita?'),
          ],
        ),
        content: Text(
            '¿Estás seguro de que deseas cancelar la visita de $nombreCliente?\n\n'
            'La borraremos de esta aplicación y abriremos tu Google Calendar para que la elimines permanentemente de tu teléfono.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Volver', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              setState(() {
                _citasGuardadas.removeAt(index);
              });

              Navigator.pop(context);
              _mostrarMensaje(
                  '🗑️ Cita borrada de la app. Abriendo Google Calendar...',
                  KazaColores.naranja);

              await Future.delayed(const Duration(milliseconds: 800));
              await _redirigirParaBorrar(fechaHora);
            },
            child: const Text(
              'Sí, Cancelar',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _limpiarFormulario() {
    _nombreCtrl.clear();
    _telefonoCtrl.clear();
    _ubicacionCtrl.clear();
    setState(() {
      _fechaSeleccionada = null;
      _horaSeleccionada = null;
      _tipoCitaSeleccionado = null; // Reiniciar dropdown
    });
  }

  void _mostrarMensaje(String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    String txtFecha = _fechaSeleccionada == null
        ? 'Elegir Día'
        : '${_fechaSeleccionada!.day.toString().padLeft(2, '0')}/${_fechaSeleccionada!.month.toString().padLeft(2, '0')}/${_fechaSeleccionada!.year}';

    String txtHora = _horaSeleccionada == null
        ? 'Elegir Hora'
        : '${_horaSeleccionada!.hour.toString().padLeft(2, '0')}:${_horaSeleccionada!.minute.toString().padLeft(2, '0')}';

    // Ordenar cronológicamente
    List<Map<String, String>> citasOrdenadas = List.from(_citasGuardadas);
    citasOrdenadas.sort((a, b) => a['fechaHora']!.compareTo(b['fechaHora']!));

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- LOGOTIPO KAZA ---
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  decoration: BoxDecoration(
                    color: KazaColores.blanco,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: KazaColores.azulMarino,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.home,
                                color: KazaColores.blanco, size: 28),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'K',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: KazaColores.naranja,
                            ),
                          ),
                          const Text(
                            'aza',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: KazaColores.azulMarino,
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Creando hogares',
                        style: TextStyle(
                          fontSize: 14,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // --- CAMPOS DE TEXTO ---
              const Text(
                'Datos del Prospecto / Cliente',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: KazaColores.azulMarino),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre Completo del Cliente',
                  prefixIcon: Icon(Icons.person, color: KazaColores.azulMarino),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: KazaColores.blanco,
                ),
              ),
              const SizedBox(height: 14),

              // --- NUEVO: COMBOBOX (TIPO DE CITA) ---
              DropdownButtonFormField<String>(
                value: _tipoCitaSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Motivo / Tipo de Cita',
                  prefixIcon:
                      Icon(Icons.assignment, color: KazaColores.azulMarino),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: KazaColores.blanco,
                ),
                hint: const Text('Selecciona una opción'),
                iconEnabledColor: KazaColores.naranja,
                items: _tiposDeCita.map((String valor) {
                  return DropdownMenuItem<String>(
                    value: valor,
                    child: Text(valor),
                  );
                }).toList(),
                onChanged: (String? nuevoValor) {
                  setState(() {
                    _tipoCitaSeleccionado = nuevoValor;
                  });
                },
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono de Contacto (Opcional)',
                  prefixIcon: Icon(Icons.phone, color: KazaColores.azulMarino),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: KazaColores.blanco,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ubicacionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ubicación / Dirección de la Cita',
                  prefixIcon:
                      Icon(Icons.location_on, color: KazaColores.azulMarino),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: KazaColores.blanco,
                ),
              ),
              const SizedBox(height: 25),

              // --- SELECCIÓN DE FECHA Y HORA ---
              const Text(
                'Fecha y Hora de la Cita (24 hrs)',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: KazaColores.azulMarino),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KazaColores.naranja.withOpacity(0.1),
                        foregroundColor: KazaColores.naranja,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _elegirFecha,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(txtFecha,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: KazaColores.naranja.withOpacity(0.1),
                        foregroundColor: KazaColores.naranja,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _elegirHora,
                      icon: const Icon(Icons.access_time),
                      label: Text(txtHora,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),

              // --- BOTÓN PRINCIPAL DE AGENDADO ---
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: KazaColores.azulMarino,
                  foregroundColor: KazaColores.blanco,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 2,
                ),
                onPressed: _procesarCita,
                child: const Text(
                  'AGENDAR VISITA KAZA 🚀',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1),
                ),
              ),

              const SizedBox(height: 40),

              // --- AGENDA DE CITAS PROGRAMADAS ---
              const Row(
                children: [
                  Icon(Icons.calendar_month, color: KazaColores.azulMarino),
                  SizedBox(width: 8),
                  Text(
                    'Agenda de Visitas - Kaza',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: KazaColores.azulMarino),
                  ),
                ],
              ),
              const Divider(color: KazaColores.naranja, thickness: 1.5),
              const SizedBox(height: 10),

              // Lista visual dinámica
              citasOrdenadas.isEmpty
                  ? const Card(
                      color: KazaColores.blanco,
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'No hay visitas programadas. ¡Comienza a agendar arriba!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: citasOrdenadas.length,
                      itemBuilder: (context, index) {
                        final cita = citasOrdenadas[index];

                        List<String> partes = cita['fechaHora']!.split(' ');
                        String fechaLimpia = partes[0];
                        String horaLimpia = partes[1];

                        // Encontramos de forma segura el índice real en la lista original
                        int indiceOriginal = _citasGuardadas.indexOf(cita);

                        String nombreYMotivo =
                            '${cita['nombre']} (${cita['tipo']})';

                        return Card(
                          color: KazaColores.blanco,
                          elevation: 1,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        nombreYMotivo,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: KazaColores.azulMarino,
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: KazaColores.azulMarino,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '$horaLimpia hrs',
                                            style: const TextStyle(
                                              color: KazaColores.blanco,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              color: KazaColores.naranja),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () =>
                                              _confirmarCancelacion(
                                                  indiceOriginal,
                                                  nombreYMotivo,
                                                  cita['fechaHora']!),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 6),
                                    Text(
                                      fechaLimpia,
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 13),
                                    ),
                                    const SizedBox(width: 15),
                                    const Icon(Icons.location_on,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '${cita['ubicacion']}',
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
