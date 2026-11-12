import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/shop_repository.dart';
import '../../services/session.dart';
import '../common.dart';
import '../sales/credits_screen.dart';

/// Carnet de clients : téléphone, tarif attitré, plafond de crédit, reste dû.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clients')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientFormScreen())),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Nouveau client'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nom ou téléphone'),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: Reloading<(List<Client>, List<PriceLevel>)>(
              deps: [_search],
              load: (r, u) async => (await r.clientList(u, search: _search), await r.priceLevels(u)),
              builder: (context, data) {
                final (clients, levels) = data;
                if (clients.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline,
                    message: _search.isEmpty
                        ? 'Aucun client. Les clients sont aussi ajoutés automatiquement à la vente.'
                        : 'Aucun client trouvé.',
                  );
                }
                final levelName = {for (final l in levels) l.id: l.name};
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: clients.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = clients[i];
                    final details = [
                      if ((c.phone ?? '').isNotEmpty) c.phone!,
                      if (c.priceLevelId != null && levelName[c.priceLevelId] != null) 'Tarif ${levelName[c.priceLevelId]}',
                      if (c.creditLimit > 0) 'Plafond ${Fmt.money(c.creditLimit)}',
                    ];
                    return ListTile(
                      leading: CircleAvatar(child: Text(c.name.characters.first.toUpperCase())),
                      title: Text(c.name),
                      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
                      trailing: c.balance >= 1
                          ? Text(
                              Fmt.money(c.balance),
                              style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold),
                            )
                          : null,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientFormScreen(client: c))),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ClientFormScreen extends StatefulWidget {
  const ClientFormScreen({super.key, this.client});
  final Client? client;

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.client?.name ?? '');
  late final _phone = TextEditingController(text: widget.client?.phone ?? '');
  late final _address = TextEditingController(text: widget.client?.address ?? '');
  late final _niu = TextEditingController(text: widget.client?.niu ?? '');
  late final _limit = TextEditingController(
    text: (widget.client?.creditLimit ?? 0) > 0 ? widget.client!.creditLimit.round().toString() : '',
  );
  late final _note = TextEditingController(text: widget.client?.note ?? '');
  late int? _levelId = widget.client?.priceLevelId;
  List<PriceLevel> _levels = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<ShopRepository>().priceLevels(context.read<Session>().userId).then((l) {
      if (mounted) setState(() => _levels = l);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _niu, _limit, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<ShopRepository>().saveClient(
        context.read<Session>().userId,
        Client(
          id: widget.client?.id,
          name: _name.text,
          phone: _phone.text,
          address: _address.text,
          niu: _niu.text,
          priceLevelId: _levelId,
          creditLimit: Fmt.parseNumber(_limit.text) ?? 0,
          note: _note.text,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final c = widget.client!;
    final ok = await confirm(
      context,
      'Supprimer la fiche de ${c.name} ?',
      'Ses ventes passées restent dans l\'historique.',
      ok: 'Supprimer',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await context.read<ShopRepository>().deleteClient(context.read<Session>().userId, c.id!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Nouveau client' : c.name),
        actions: [
          if (c != null)
            IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (c != null && c.balance >= 1)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text('Reste dû : ${Fmt.money(c.balance)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ClientCreditScreen(client: c.name)),
                  ),
                ),
              ),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nom *', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Adresse', prefixIcon: Icon(Icons.place_outlined)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _niu,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'NIU du client (entreprises)',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SectionTitle('Conditions commerciales'),
            DropdownButtonFormField<int?>(
              initialValue: _levels.any((l) => l.id == _levelId) ? _levelId : null,
              decoration: const InputDecoration(labelText: 'Tarif attitré', prefixIcon: Icon(Icons.local_offer_outlined)),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Détail (prix normal)')),
                for (final l in _levels) DropdownMenuItem<int?>(value: l.id, child: Text(l.name)),
              ],
              onChanged: (v) => setState(() => _levelId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _limit,
              keyboardType: TextInputType.number,
              inputFormatters: intInput,
              decoration: const InputDecoration(
                labelText: 'Plafond de crédit',
                suffixText: 'FCFA',
                helperText: 'Vide = pas de plafond. Au-delà, la vente à crédit est refusée.',
                prefixIcon: Icon(Icons.shield_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note', prefixIcon: Icon(Icons.notes)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
