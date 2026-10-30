// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'yerel_db.dart';

// ignore_for_file: type=lint
class $KuyrukTable extends Kuyruk with TableInfo<$KuyrukTable, KuyrukData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KuyrukTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localSeqMeta = const VerificationMeta(
    'localSeq',
  );
  @override
  late final GeneratedColumn<int> localSeq = GeneratedColumn<int>(
    'local_seq',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fnMeta = const VerificationMeta('fn');
  @override
  late final GeneratedColumn<String> fn = GeneratedColumn<String>(
    'fn',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _argsMeta = const VerificationMeta('args');
  @override
  late final GeneratedColumn<String> args = GeneratedColumn<String>(
    'args',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durumMeta = const VerificationMeta('durum');
  @override
  late final GeneratedColumn<String> durum = GeneratedColumn<String>(
    'durum',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('bekliyor'),
  );
  static const VerificationMeta _hataMeta = const VerificationMeta('hata');
  @override
  late final GeneratedColumn<String> hata = GeneratedColumn<String>(
    'hata',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ozetMeta = const VerificationMeta('ozet');
  @override
  late final GeneratedColumn<String> ozet = GeneratedColumn<String>(
    'ozet',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _olusturmaLocalMeta = const VerificationMeta(
    'olusturmaLocal',
  );
  @override
  late final GeneratedColumn<DateTime> olusturmaLocal =
      GeneratedColumn<DateTime>(
        'olusturma_local',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _denemeMeta = const VerificationMeta('deneme');
  @override
  late final GeneratedColumn<int> deneme = GeneratedColumn<int>(
    'deneme',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sonucJsonMeta = const VerificationMeta(
    'sonucJson',
  );
  @override
  late final GeneratedColumn<String> sonucJson = GeneratedColumn<String>(
    'sonuc_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localSeq,
    fn,
    args,
    durum,
    hata,
    ozet,
    olusturmaLocal,
    deneme,
    sonucJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kuyruk';
  @override
  VerificationContext validateIntegrity(
    Insertable<KuyrukData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_seq')) {
      context.handle(
        _localSeqMeta,
        localSeq.isAcceptableOrUnknown(data['local_seq']!, _localSeqMeta),
      );
    }
    if (data.containsKey('fn')) {
      context.handle(_fnMeta, fn.isAcceptableOrUnknown(data['fn']!, _fnMeta));
    } else if (isInserting) {
      context.missing(_fnMeta);
    }
    if (data.containsKey('args')) {
      context.handle(
        _argsMeta,
        args.isAcceptableOrUnknown(data['args']!, _argsMeta),
      );
    } else if (isInserting) {
      context.missing(_argsMeta);
    }
    if (data.containsKey('durum')) {
      context.handle(
        _durumMeta,
        durum.isAcceptableOrUnknown(data['durum']!, _durumMeta),
      );
    }
    if (data.containsKey('hata')) {
      context.handle(
        _hataMeta,
        hata.isAcceptableOrUnknown(data['hata']!, _hataMeta),
      );
    }
    if (data.containsKey('ozet')) {
      context.handle(
        _ozetMeta,
        ozet.isAcceptableOrUnknown(data['ozet']!, _ozetMeta),
      );
    } else if (isInserting) {
      context.missing(_ozetMeta);
    }
    if (data.containsKey('olusturma_local')) {
      context.handle(
        _olusturmaLocalMeta,
        olusturmaLocal.isAcceptableOrUnknown(
          data['olusturma_local']!,
          _olusturmaLocalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_olusturmaLocalMeta);
    }
    if (data.containsKey('deneme')) {
      context.handle(
        _denemeMeta,
        deneme.isAcceptableOrUnknown(data['deneme']!, _denemeMeta),
      );
    }
    if (data.containsKey('sonuc_json')) {
      context.handle(
        _sonucJsonMeta,
        sonucJson.isAcceptableOrUnknown(data['sonuc_json']!, _sonucJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localSeq};
  @override
  KuyrukData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KuyrukData(
      localSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_seq'],
      )!,
      fn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fn'],
      )!,
      args: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}args'],
      )!,
      durum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}durum'],
      )!,
      hata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hata'],
      ),
      ozet: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ozet'],
      )!,
      olusturmaLocal: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}olusturma_local'],
      )!,
      deneme: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deneme'],
      )!,
      sonucJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sonuc_json'],
      ),
    );
  }

  @override
  $KuyrukTable createAlias(String alias) {
    return $KuyrukTable(attachedDatabase, alias);
  }
}

class KuyrukData extends DataClass implements Insertable<KuyrukData> {
  final int localSeq;
  final String fn;
  final String args;

  /// bekliyor · yuklendi · hata
  final String durum;
  final String? hata;

  /// Kullanıcıya gösterilecek satır: "Y Lisesi · 3 kalem talep".
  /// Kuyruğu ham fonksiyon adıyla göstermek kimseye bir şey anlatmaz.
  final String ozet;

  /// Cihaz saati (K43 · kural 4). Sıralama ipucudur, rapor kaynağı değildir.
  final DateTime olusturmaLocal;
  final int deneme;
  final String? sonucJson;
  const KuyrukData({
    required this.localSeq,
    required this.fn,
    required this.args,
    required this.durum,
    this.hata,
    required this.ozet,
    required this.olusturmaLocal,
    required this.deneme,
    this.sonucJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_seq'] = Variable<int>(localSeq);
    map['fn'] = Variable<String>(fn);
    map['args'] = Variable<String>(args);
    map['durum'] = Variable<String>(durum);
    if (!nullToAbsent || hata != null) {
      map['hata'] = Variable<String>(hata);
    }
    map['ozet'] = Variable<String>(ozet);
    map['olusturma_local'] = Variable<DateTime>(olusturmaLocal);
    map['deneme'] = Variable<int>(deneme);
    if (!nullToAbsent || sonucJson != null) {
      map['sonuc_json'] = Variable<String>(sonucJson);
    }
    return map;
  }

  KuyrukCompanion toCompanion(bool nullToAbsent) {
    return KuyrukCompanion(
      localSeq: Value(localSeq),
      fn: Value(fn),
      args: Value(args),
      durum: Value(durum),
      hata: hata == null && nullToAbsent ? const Value.absent() : Value(hata),
      ozet: Value(ozet),
      olusturmaLocal: Value(olusturmaLocal),
      deneme: Value(deneme),
      sonucJson: sonucJson == null && nullToAbsent
          ? const Value.absent()
          : Value(sonucJson),
    );
  }

  factory KuyrukData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KuyrukData(
      localSeq: serializer.fromJson<int>(json['localSeq']),
      fn: serializer.fromJson<String>(json['fn']),
      args: serializer.fromJson<String>(json['args']),
      durum: serializer.fromJson<String>(json['durum']),
      hata: serializer.fromJson<String?>(json['hata']),
      ozet: serializer.fromJson<String>(json['ozet']),
      olusturmaLocal: serializer.fromJson<DateTime>(json['olusturmaLocal']),
      deneme: serializer.fromJson<int>(json['deneme']),
      sonucJson: serializer.fromJson<String?>(json['sonucJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localSeq': serializer.toJson<int>(localSeq),
      'fn': serializer.toJson<String>(fn),
      'args': serializer.toJson<String>(args),
      'durum': serializer.toJson<String>(durum),
      'hata': serializer.toJson<String?>(hata),
      'ozet': serializer.toJson<String>(ozet),
      'olusturmaLocal': serializer.toJson<DateTime>(olusturmaLocal),
      'deneme': serializer.toJson<int>(deneme),
      'sonucJson': serializer.toJson<String?>(sonucJson),
    };
  }

  KuyrukData copyWith({
    int? localSeq,
    String? fn,
    String? args,
    String? durum,
    Value<String?> hata = const Value.absent(),
    String? ozet,
    DateTime? olusturmaLocal,
    int? deneme,
    Value<String?> sonucJson = const Value.absent(),
  }) => KuyrukData(
    localSeq: localSeq ?? this.localSeq,
    fn: fn ?? this.fn,
    args: args ?? this.args,
    durum: durum ?? this.durum,
    hata: hata.present ? hata.value : this.hata,
    ozet: ozet ?? this.ozet,
    olusturmaLocal: olusturmaLocal ?? this.olusturmaLocal,
    deneme: deneme ?? this.deneme,
    sonucJson: sonucJson.present ? sonucJson.value : this.sonucJson,
  );
  KuyrukData copyWithCompanion(KuyrukCompanion data) {
    return KuyrukData(
      localSeq: data.localSeq.present ? data.localSeq.value : this.localSeq,
      fn: data.fn.present ? data.fn.value : this.fn,
      args: data.args.present ? data.args.value : this.args,
      durum: data.durum.present ? data.durum.value : this.durum,
      hata: data.hata.present ? data.hata.value : this.hata,
      ozet: data.ozet.present ? data.ozet.value : this.ozet,
      olusturmaLocal: data.olusturmaLocal.present
          ? data.olusturmaLocal.value
          : this.olusturmaLocal,
      deneme: data.deneme.present ? data.deneme.value : this.deneme,
      sonucJson: data.sonucJson.present ? data.sonucJson.value : this.sonucJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KuyrukData(')
          ..write('localSeq: $localSeq, ')
          ..write('fn: $fn, ')
          ..write('args: $args, ')
          ..write('durum: $durum, ')
          ..write('hata: $hata, ')
          ..write('ozet: $ozet, ')
          ..write('olusturmaLocal: $olusturmaLocal, ')
          ..write('deneme: $deneme, ')
          ..write('sonucJson: $sonucJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localSeq,
    fn,
    args,
    durum,
    hata,
    ozet,
    olusturmaLocal,
    deneme,
    sonucJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KuyrukData &&
          other.localSeq == this.localSeq &&
          other.fn == this.fn &&
          other.args == this.args &&
          other.durum == this.durum &&
          other.hata == this.hata &&
          other.ozet == this.ozet &&
          other.olusturmaLocal == this.olusturmaLocal &&
          other.deneme == this.deneme &&
          other.sonucJson == this.sonucJson);
}

class KuyrukCompanion extends UpdateCompanion<KuyrukData> {
  final Value<int> localSeq;
  final Value<String> fn;
  final Value<String> args;
  final Value<String> durum;
  final Value<String?> hata;
  final Value<String> ozet;
  final Value<DateTime> olusturmaLocal;
  final Value<int> deneme;
  final Value<String?> sonucJson;
  const KuyrukCompanion({
    this.localSeq = const Value.absent(),
    this.fn = const Value.absent(),
    this.args = const Value.absent(),
    this.durum = const Value.absent(),
    this.hata = const Value.absent(),
    this.ozet = const Value.absent(),
    this.olusturmaLocal = const Value.absent(),
    this.deneme = const Value.absent(),
    this.sonucJson = const Value.absent(),
  });
  KuyrukCompanion.insert({
    this.localSeq = const Value.absent(),
    required String fn,
    required String args,
    this.durum = const Value.absent(),
    this.hata = const Value.absent(),
    required String ozet,
    required DateTime olusturmaLocal,
    this.deneme = const Value.absent(),
    this.sonucJson = const Value.absent(),
  }) : fn = Value(fn),
       args = Value(args),
       ozet = Value(ozet),
       olusturmaLocal = Value(olusturmaLocal);
  static Insertable<KuyrukData> custom({
    Expression<int>? localSeq,
    Expression<String>? fn,
    Expression<String>? args,
    Expression<String>? durum,
    Expression<String>? hata,
    Expression<String>? ozet,
    Expression<DateTime>? olusturmaLocal,
    Expression<int>? deneme,
    Expression<String>? sonucJson,
  }) {
    return RawValuesInsertable({
      if (localSeq != null) 'local_seq': localSeq,
      if (fn != null) 'fn': fn,
      if (args != null) 'args': args,
      if (durum != null) 'durum': durum,
      if (hata != null) 'hata': hata,
      if (ozet != null) 'ozet': ozet,
      if (olusturmaLocal != null) 'olusturma_local': olusturmaLocal,
      if (deneme != null) 'deneme': deneme,
      if (sonucJson != null) 'sonuc_json': sonucJson,
    });
  }

  KuyrukCompanion copyWith({
    Value<int>? localSeq,
    Value<String>? fn,
    Value<String>? args,
    Value<String>? durum,
    Value<String?>? hata,
    Value<String>? ozet,
    Value<DateTime>? olusturmaLocal,
    Value<int>? deneme,
    Value<String?>? sonucJson,
  }) {
    return KuyrukCompanion(
      localSeq: localSeq ?? this.localSeq,
      fn: fn ?? this.fn,
      args: args ?? this.args,
      durum: durum ?? this.durum,
      hata: hata ?? this.hata,
      ozet: ozet ?? this.ozet,
      olusturmaLocal: olusturmaLocal ?? this.olusturmaLocal,
      deneme: deneme ?? this.deneme,
      sonucJson: sonucJson ?? this.sonucJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localSeq.present) {
      map['local_seq'] = Variable<int>(localSeq.value);
    }
    if (fn.present) {
      map['fn'] = Variable<String>(fn.value);
    }
    if (args.present) {
      map['args'] = Variable<String>(args.value);
    }
    if (durum.present) {
      map['durum'] = Variable<String>(durum.value);
    }
    if (hata.present) {
      map['hata'] = Variable<String>(hata.value);
    }
    if (ozet.present) {
      map['ozet'] = Variable<String>(ozet.value);
    }
    if (olusturmaLocal.present) {
      map['olusturma_local'] = Variable<DateTime>(olusturmaLocal.value);
    }
    if (deneme.present) {
      map['deneme'] = Variable<int>(deneme.value);
    }
    if (sonucJson.present) {
      map['sonuc_json'] = Variable<String>(sonucJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KuyrukCompanion(')
          ..write('localSeq: $localSeq, ')
          ..write('fn: $fn, ')
          ..write('args: $args, ')
          ..write('durum: $durum, ')
          ..write('hata: $hata, ')
          ..write('ozet: $ozet, ')
          ..write('olusturmaLocal: $olusturmaLocal, ')
          ..write('deneme: $deneme, ')
          ..write('sonucJson: $sonucJson')
          ..write(')'))
        .toString();
  }
}

class $YerelCariTable extends YerelCari
    with TableInfo<$YerelCariTable, YerelCariData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $YerelCariTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unvanMeta = const VerificationMeta('unvan');
  @override
  late final GeneratedColumn<String> unvan = GeneratedColumn<String>(
    'unvan',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tipMeta = const VerificationMeta('tip');
  @override
  late final GeneratedColumn<String> tip = GeneratedColumn<String>(
    'tip',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durumMeta = const VerificationMeta('durum');
  @override
  late final GeneratedColumn<String> durum = GeneratedColumn<String>(
    'durum',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kurumIdMeta = const VerificationMeta(
    'kurumId',
  );
  @override
  late final GeneratedColumn<String> kurumId = GeneratedColumn<String>(
    'kurum_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bakiyeMeta = const VerificationMeta('bakiye');
  @override
  late final GeneratedColumn<double> bakiye = GeneratedColumn<double>(
    'bakiye',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _krediLimitiMeta = const VerificationMeta(
    'krediLimiti',
  );
  @override
  late final GeneratedColumn<double> krediLimiti = GeneratedColumn<double>(
    'kredi_limiti',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _kademeMeta = const VerificationMeta('kademe');
  @override
  late final GeneratedColumn<String> kademe = GeneratedColumn<String>(
    'kademe',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    unvan,
    tip,
    durum,
    kurumId,
    bakiye,
    krediLimiti,
    kademe,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'yerel_cari';
  @override
  VerificationContext validateIntegrity(
    Insertable<YerelCariData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('unvan')) {
      context.handle(
        _unvanMeta,
        unvan.isAcceptableOrUnknown(data['unvan']!, _unvanMeta),
      );
    } else if (isInserting) {
      context.missing(_unvanMeta);
    }
    if (data.containsKey('tip')) {
      context.handle(
        _tipMeta,
        tip.isAcceptableOrUnknown(data['tip']!, _tipMeta),
      );
    } else if (isInserting) {
      context.missing(_tipMeta);
    }
    if (data.containsKey('durum')) {
      context.handle(
        _durumMeta,
        durum.isAcceptableOrUnknown(data['durum']!, _durumMeta),
      );
    } else if (isInserting) {
      context.missing(_durumMeta);
    }
    if (data.containsKey('kurum_id')) {
      context.handle(
        _kurumIdMeta,
        kurumId.isAcceptableOrUnknown(data['kurum_id']!, _kurumIdMeta),
      );
    }
    if (data.containsKey('bakiye')) {
      context.handle(
        _bakiyeMeta,
        bakiye.isAcceptableOrUnknown(data['bakiye']!, _bakiyeMeta),
      );
    }
    if (data.containsKey('kredi_limiti')) {
      context.handle(
        _krediLimitiMeta,
        krediLimiti.isAcceptableOrUnknown(
          data['kredi_limiti']!,
          _krediLimitiMeta,
        ),
      );
    }
    if (data.containsKey('kademe')) {
      context.handle(
        _kademeMeta,
        kademe.isAcceptableOrUnknown(data['kademe']!, _kademeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  YerelCariData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return YerelCariData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      unvan: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unvan'],
      )!,
      tip: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tip'],
      )!,
      durum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}durum'],
      )!,
      kurumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kurum_id'],
      ),
      bakiye: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bakiye'],
      )!,
      krediLimiti: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}kredi_limiti'],
      )!,
      kademe: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kademe'],
      ),
    );
  }

  @override
  $YerelCariTable createAlias(String alias) {
    return $YerelCariTable(attachedDatabase, alias);
  }
}

class YerelCariData extends DataClass implements Insertable<YerelCariData> {
  final String id;
  final String unvan;
  final String tip;
  final String durum;
  final String? kurumId;
  final double bakiye;
  final double krediLimiti;
  final String? kademe;
  const YerelCariData({
    required this.id,
    required this.unvan,
    required this.tip,
    required this.durum,
    this.kurumId,
    required this.bakiye,
    required this.krediLimiti,
    this.kademe,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['unvan'] = Variable<String>(unvan);
    map['tip'] = Variable<String>(tip);
    map['durum'] = Variable<String>(durum);
    if (!nullToAbsent || kurumId != null) {
      map['kurum_id'] = Variable<String>(kurumId);
    }
    map['bakiye'] = Variable<double>(bakiye);
    map['kredi_limiti'] = Variable<double>(krediLimiti);
    if (!nullToAbsent || kademe != null) {
      map['kademe'] = Variable<String>(kademe);
    }
    return map;
  }

  YerelCariCompanion toCompanion(bool nullToAbsent) {
    return YerelCariCompanion(
      id: Value(id),
      unvan: Value(unvan),
      tip: Value(tip),
      durum: Value(durum),
      kurumId: kurumId == null && nullToAbsent
          ? const Value.absent()
          : Value(kurumId),
      bakiye: Value(bakiye),
      krediLimiti: Value(krediLimiti),
      kademe: kademe == null && nullToAbsent
          ? const Value.absent()
          : Value(kademe),
    );
  }

  factory YerelCariData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return YerelCariData(
      id: serializer.fromJson<String>(json['id']),
      unvan: serializer.fromJson<String>(json['unvan']),
      tip: serializer.fromJson<String>(json['tip']),
      durum: serializer.fromJson<String>(json['durum']),
      kurumId: serializer.fromJson<String?>(json['kurumId']),
      bakiye: serializer.fromJson<double>(json['bakiye']),
      krediLimiti: serializer.fromJson<double>(json['krediLimiti']),
      kademe: serializer.fromJson<String?>(json['kademe']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'unvan': serializer.toJson<String>(unvan),
      'tip': serializer.toJson<String>(tip),
      'durum': serializer.toJson<String>(durum),
      'kurumId': serializer.toJson<String?>(kurumId),
      'bakiye': serializer.toJson<double>(bakiye),
      'krediLimiti': serializer.toJson<double>(krediLimiti),
      'kademe': serializer.toJson<String?>(kademe),
    };
  }

  YerelCariData copyWith({
    String? id,
    String? unvan,
    String? tip,
    String? durum,
    Value<String?> kurumId = const Value.absent(),
    double? bakiye,
    double? krediLimiti,
    Value<String?> kademe = const Value.absent(),
  }) => YerelCariData(
    id: id ?? this.id,
    unvan: unvan ?? this.unvan,
    tip: tip ?? this.tip,
    durum: durum ?? this.durum,
    kurumId: kurumId.present ? kurumId.value : this.kurumId,
    bakiye: bakiye ?? this.bakiye,
    krediLimiti: krediLimiti ?? this.krediLimiti,
    kademe: kademe.present ? kademe.value : this.kademe,
  );
  YerelCariData copyWithCompanion(YerelCariCompanion data) {
    return YerelCariData(
      id: data.id.present ? data.id.value : this.id,
      unvan: data.unvan.present ? data.unvan.value : this.unvan,
      tip: data.tip.present ? data.tip.value : this.tip,
      durum: data.durum.present ? data.durum.value : this.durum,
      kurumId: data.kurumId.present ? data.kurumId.value : this.kurumId,
      bakiye: data.bakiye.present ? data.bakiye.value : this.bakiye,
      krediLimiti: data.krediLimiti.present
          ? data.krediLimiti.value
          : this.krediLimiti,
      kademe: data.kademe.present ? data.kademe.value : this.kademe,
    );
  }

  @override
  String toString() {
    return (StringBuffer('YerelCariData(')
          ..write('id: $id, ')
          ..write('unvan: $unvan, ')
          ..write('tip: $tip, ')
          ..write('durum: $durum, ')
          ..write('kurumId: $kurumId, ')
          ..write('bakiye: $bakiye, ')
          ..write('krediLimiti: $krediLimiti, ')
          ..write('kademe: $kademe')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, unvan, tip, durum, kurumId, bakiye, krediLimiti, kademe);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is YerelCariData &&
          other.id == this.id &&
          other.unvan == this.unvan &&
          other.tip == this.tip &&
          other.durum == this.durum &&
          other.kurumId == this.kurumId &&
          other.bakiye == this.bakiye &&
          other.krediLimiti == this.krediLimiti &&
          other.kademe == this.kademe);
}

class YerelCariCompanion extends UpdateCompanion<YerelCariData> {
  final Value<String> id;
  final Value<String> unvan;
  final Value<String> tip;
  final Value<String> durum;
  final Value<String?> kurumId;
  final Value<double> bakiye;
  final Value<double> krediLimiti;
  final Value<String?> kademe;
  final Value<int> rowid;
  const YerelCariCompanion({
    this.id = const Value.absent(),
    this.unvan = const Value.absent(),
    this.tip = const Value.absent(),
    this.durum = const Value.absent(),
    this.kurumId = const Value.absent(),
    this.bakiye = const Value.absent(),
    this.krediLimiti = const Value.absent(),
    this.kademe = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  YerelCariCompanion.insert({
    required String id,
    required String unvan,
    required String tip,
    required String durum,
    this.kurumId = const Value.absent(),
    this.bakiye = const Value.absent(),
    this.krediLimiti = const Value.absent(),
    this.kademe = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       unvan = Value(unvan),
       tip = Value(tip),
       durum = Value(durum);
  static Insertable<YerelCariData> custom({
    Expression<String>? id,
    Expression<String>? unvan,
    Expression<String>? tip,
    Expression<String>? durum,
    Expression<String>? kurumId,
    Expression<double>? bakiye,
    Expression<double>? krediLimiti,
    Expression<String>? kademe,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (unvan != null) 'unvan': unvan,
      if (tip != null) 'tip': tip,
      if (durum != null) 'durum': durum,
      if (kurumId != null) 'kurum_id': kurumId,
      if (bakiye != null) 'bakiye': bakiye,
      if (krediLimiti != null) 'kredi_limiti': krediLimiti,
      if (kademe != null) 'kademe': kademe,
      if (rowid != null) 'rowid': rowid,
    });
  }

  YerelCariCompanion copyWith({
    Value<String>? id,
    Value<String>? unvan,
    Value<String>? tip,
    Value<String>? durum,
    Value<String?>? kurumId,
    Value<double>? bakiye,
    Value<double>? krediLimiti,
    Value<String?>? kademe,
    Value<int>? rowid,
  }) {
    return YerelCariCompanion(
      id: id ?? this.id,
      unvan: unvan ?? this.unvan,
      tip: tip ?? this.tip,
      durum: durum ?? this.durum,
      kurumId: kurumId ?? this.kurumId,
      bakiye: bakiye ?? this.bakiye,
      krediLimiti: krediLimiti ?? this.krediLimiti,
      kademe: kademe ?? this.kademe,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (unvan.present) {
      map['unvan'] = Variable<String>(unvan.value);
    }
    if (tip.present) {
      map['tip'] = Variable<String>(tip.value);
    }
    if (durum.present) {
      map['durum'] = Variable<String>(durum.value);
    }
    if (kurumId.present) {
      map['kurum_id'] = Variable<String>(kurumId.value);
    }
    if (bakiye.present) {
      map['bakiye'] = Variable<double>(bakiye.value);
    }
    if (krediLimiti.present) {
      map['kredi_limiti'] = Variable<double>(krediLimiti.value);
    }
    if (kademe.present) {
      map['kademe'] = Variable<String>(kademe.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('YerelCariCompanion(')
          ..write('id: $id, ')
          ..write('unvan: $unvan, ')
          ..write('tip: $tip, ')
          ..write('durum: $durum, ')
          ..write('kurumId: $kurumId, ')
          ..write('bakiye: $bakiye, ')
          ..write('krediLimiti: $krediLimiti, ')
          ..write('kademe: $kademe, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $YerelKurumTable extends YerelKurum
    with TableInfo<$YerelKurumTable, YerelKurumData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $YerelKurumTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _adMeta = const VerificationMeta('ad');
  @override
  late final GeneratedColumn<String> ad = GeneratedColumn<String>(
    'ad',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ilMeta = const VerificationMeta('il');
  @override
  late final GeneratedColumn<String> il = GeneratedColumn<String>(
    'il',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ilceMeta = const VerificationMeta('ilce');
  @override
  late final GeneratedColumn<String> ilce = GeneratedColumn<String>(
    'ilce',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tipMeta = const VerificationMeta('tip');
  @override
  late final GeneratedColumn<String> tip = GeneratedColumn<String>(
    'tip',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, ad, il, ilce, tip];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'yerel_kurum';
  @override
  VerificationContext validateIntegrity(
    Insertable<YerelKurumData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('ad')) {
      context.handle(_adMeta, ad.isAcceptableOrUnknown(data['ad']!, _adMeta));
    } else if (isInserting) {
      context.missing(_adMeta);
    }
    if (data.containsKey('il')) {
      context.handle(_ilMeta, il.isAcceptableOrUnknown(data['il']!, _ilMeta));
    }
    if (data.containsKey('ilce')) {
      context.handle(
        _ilceMeta,
        ilce.isAcceptableOrUnknown(data['ilce']!, _ilceMeta),
      );
    }
    if (data.containsKey('tip')) {
      context.handle(
        _tipMeta,
        tip.isAcceptableOrUnknown(data['tip']!, _tipMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  YerelKurumData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return YerelKurumData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ad: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ad'],
      )!,
      il: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}il'],
      ),
      ilce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ilce'],
      ),
      tip: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tip'],
      ),
    );
  }

  @override
  $YerelKurumTable createAlias(String alias) {
    return $YerelKurumTable(attachedDatabase, alias);
  }
}

class YerelKurumData extends DataClass implements Insertable<YerelKurumData> {
  final String id;
  final String ad;
  final String? il;
  final String? ilce;
  final String? tip;
  const YerelKurumData({
    required this.id,
    required this.ad,
    this.il,
    this.ilce,
    this.tip,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['ad'] = Variable<String>(ad);
    if (!nullToAbsent || il != null) {
      map['il'] = Variable<String>(il);
    }
    if (!nullToAbsent || ilce != null) {
      map['ilce'] = Variable<String>(ilce);
    }
    if (!nullToAbsent || tip != null) {
      map['tip'] = Variable<String>(tip);
    }
    return map;
  }

  YerelKurumCompanion toCompanion(bool nullToAbsent) {
    return YerelKurumCompanion(
      id: Value(id),
      ad: Value(ad),
      il: il == null && nullToAbsent ? const Value.absent() : Value(il),
      ilce: ilce == null && nullToAbsent ? const Value.absent() : Value(ilce),
      tip: tip == null && nullToAbsent ? const Value.absent() : Value(tip),
    );
  }

  factory YerelKurumData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return YerelKurumData(
      id: serializer.fromJson<String>(json['id']),
      ad: serializer.fromJson<String>(json['ad']),
      il: serializer.fromJson<String?>(json['il']),
      ilce: serializer.fromJson<String?>(json['ilce']),
      tip: serializer.fromJson<String?>(json['tip']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ad': serializer.toJson<String>(ad),
      'il': serializer.toJson<String?>(il),
      'ilce': serializer.toJson<String?>(ilce),
      'tip': serializer.toJson<String?>(tip),
    };
  }

  YerelKurumData copyWith({
    String? id,
    String? ad,
    Value<String?> il = const Value.absent(),
    Value<String?> ilce = const Value.absent(),
    Value<String?> tip = const Value.absent(),
  }) => YerelKurumData(
    id: id ?? this.id,
    ad: ad ?? this.ad,
    il: il.present ? il.value : this.il,
    ilce: ilce.present ? ilce.value : this.ilce,
    tip: tip.present ? tip.value : this.tip,
  );
  YerelKurumData copyWithCompanion(YerelKurumCompanion data) {
    return YerelKurumData(
      id: data.id.present ? data.id.value : this.id,
      ad: data.ad.present ? data.ad.value : this.ad,
      il: data.il.present ? data.il.value : this.il,
      ilce: data.ilce.present ? data.ilce.value : this.ilce,
      tip: data.tip.present ? data.tip.value : this.tip,
    );
  }

  @override
  String toString() {
    return (StringBuffer('YerelKurumData(')
          ..write('id: $id, ')
          ..write('ad: $ad, ')
          ..write('il: $il, ')
          ..write('ilce: $ilce, ')
          ..write('tip: $tip')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, ad, il, ilce, tip);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is YerelKurumData &&
          other.id == this.id &&
          other.ad == this.ad &&
          other.il == this.il &&
          other.ilce == this.ilce &&
          other.tip == this.tip);
}

class YerelKurumCompanion extends UpdateCompanion<YerelKurumData> {
  final Value<String> id;
  final Value<String> ad;
  final Value<String?> il;
  final Value<String?> ilce;
  final Value<String?> tip;
  final Value<int> rowid;
  const YerelKurumCompanion({
    this.id = const Value.absent(),
    this.ad = const Value.absent(),
    this.il = const Value.absent(),
    this.ilce = const Value.absent(),
    this.tip = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  YerelKurumCompanion.insert({
    required String id,
    required String ad,
    this.il = const Value.absent(),
    this.ilce = const Value.absent(),
    this.tip = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ad = Value(ad);
  static Insertable<YerelKurumData> custom({
    Expression<String>? id,
    Expression<String>? ad,
    Expression<String>? il,
    Expression<String>? ilce,
    Expression<String>? tip,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ad != null) 'ad': ad,
      if (il != null) 'il': il,
      if (ilce != null) 'ilce': ilce,
      if (tip != null) 'tip': tip,
      if (rowid != null) 'rowid': rowid,
    });
  }

  YerelKurumCompanion copyWith({
    Value<String>? id,
    Value<String>? ad,
    Value<String?>? il,
    Value<String?>? ilce,
    Value<String?>? tip,
    Value<int>? rowid,
  }) {
    return YerelKurumCompanion(
      id: id ?? this.id,
      ad: ad ?? this.ad,
      il: il ?? this.il,
      ilce: ilce ?? this.ilce,
      tip: tip ?? this.tip,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ad.present) {
      map['ad'] = Variable<String>(ad.value);
    }
    if (il.present) {
      map['il'] = Variable<String>(il.value);
    }
    if (ilce.present) {
      map['ilce'] = Variable<String>(ilce.value);
    }
    if (tip.present) {
      map['tip'] = Variable<String>(tip.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('YerelKurumCompanion(')
          ..write('id: $id, ')
          ..write('ad: $ad, ')
          ..write('il: $il, ')
          ..write('ilce: $ilce, ')
          ..write('tip: $tip, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $YerelKisiTable extends YerelKisi
    with TableInfo<$YerelKisiTable, YerelKisiData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $YerelKisiTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kurumIdMeta = const VerificationMeta(
    'kurumId',
  );
  @override
  late final GeneratedColumn<String> kurumId = GeneratedColumn<String>(
    'kurum_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _adSoyadMeta = const VerificationMeta(
    'adSoyad',
  );
  @override
  late final GeneratedColumn<String> adSoyad = GeneratedColumn<String>(
    'ad_soyad',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gorevMeta = const VerificationMeta('gorev');
  @override
  late final GeneratedColumn<String> gorev = GeneratedColumn<String>(
    'gorev',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bransMeta = const VerificationMeta('brans');
  @override
  late final GeneratedColumn<String> brans = GeneratedColumn<String>(
    'brans',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _telefonMeta = const VerificationMeta(
    'telefon',
  );
  @override
  late final GeneratedColumn<String> telefon = GeneratedColumn<String>(
    'telefon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kurumId,
    adSoyad,
    gorev,
    brans,
    telefon,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'yerel_kisi';
  @override
  VerificationContext validateIntegrity(
    Insertable<YerelKisiData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kurum_id')) {
      context.handle(
        _kurumIdMeta,
        kurumId.isAcceptableOrUnknown(data['kurum_id']!, _kurumIdMeta),
      );
    } else if (isInserting) {
      context.missing(_kurumIdMeta);
    }
    if (data.containsKey('ad_soyad')) {
      context.handle(
        _adSoyadMeta,
        adSoyad.isAcceptableOrUnknown(data['ad_soyad']!, _adSoyadMeta),
      );
    } else if (isInserting) {
      context.missing(_adSoyadMeta);
    }
    if (data.containsKey('gorev')) {
      context.handle(
        _gorevMeta,
        gorev.isAcceptableOrUnknown(data['gorev']!, _gorevMeta),
      );
    }
    if (data.containsKey('brans')) {
      context.handle(
        _bransMeta,
        brans.isAcceptableOrUnknown(data['brans']!, _bransMeta),
      );
    }
    if (data.containsKey('telefon')) {
      context.handle(
        _telefonMeta,
        telefon.isAcceptableOrUnknown(data['telefon']!, _telefonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  YerelKisiData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return YerelKisiData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kurumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kurum_id'],
      )!,
      adSoyad: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ad_soyad'],
      )!,
      gorev: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gorev'],
      ),
      brans: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brans'],
      ),
      telefon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}telefon'],
      ),
    );
  }

  @override
  $YerelKisiTable createAlias(String alias) {
    return $YerelKisiTable(attachedDatabase, alias);
  }
}

class YerelKisiData extends DataClass implements Insertable<YerelKisiData> {
  final String id;
  final String kurumId;
  final String adSoyad;
  final String? gorev;
  final String? brans;
  final String? telefon;
  const YerelKisiData({
    required this.id,
    required this.kurumId,
    required this.adSoyad,
    this.gorev,
    this.brans,
    this.telefon,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kurum_id'] = Variable<String>(kurumId);
    map['ad_soyad'] = Variable<String>(adSoyad);
    if (!nullToAbsent || gorev != null) {
      map['gorev'] = Variable<String>(gorev);
    }
    if (!nullToAbsent || brans != null) {
      map['brans'] = Variable<String>(brans);
    }
    if (!nullToAbsent || telefon != null) {
      map['telefon'] = Variable<String>(telefon);
    }
    return map;
  }

  YerelKisiCompanion toCompanion(bool nullToAbsent) {
    return YerelKisiCompanion(
      id: Value(id),
      kurumId: Value(kurumId),
      adSoyad: Value(adSoyad),
      gorev: gorev == null && nullToAbsent
          ? const Value.absent()
          : Value(gorev),
      brans: brans == null && nullToAbsent
          ? const Value.absent()
          : Value(brans),
      telefon: telefon == null && nullToAbsent
          ? const Value.absent()
          : Value(telefon),
    );
  }

  factory YerelKisiData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return YerelKisiData(
      id: serializer.fromJson<String>(json['id']),
      kurumId: serializer.fromJson<String>(json['kurumId']),
      adSoyad: serializer.fromJson<String>(json['adSoyad']),
      gorev: serializer.fromJson<String?>(json['gorev']),
      brans: serializer.fromJson<String?>(json['brans']),
      telefon: serializer.fromJson<String?>(json['telefon']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kurumId': serializer.toJson<String>(kurumId),
      'adSoyad': serializer.toJson<String>(adSoyad),
      'gorev': serializer.toJson<String?>(gorev),
      'brans': serializer.toJson<String?>(brans),
      'telefon': serializer.toJson<String?>(telefon),
    };
  }

  YerelKisiData copyWith({
    String? id,
    String? kurumId,
    String? adSoyad,
    Value<String?> gorev = const Value.absent(),
    Value<String?> brans = const Value.absent(),
    Value<String?> telefon = const Value.absent(),
  }) => YerelKisiData(
    id: id ?? this.id,
    kurumId: kurumId ?? this.kurumId,
    adSoyad: adSoyad ?? this.adSoyad,
    gorev: gorev.present ? gorev.value : this.gorev,
    brans: brans.present ? brans.value : this.brans,
    telefon: telefon.present ? telefon.value : this.telefon,
  );
  YerelKisiData copyWithCompanion(YerelKisiCompanion data) {
    return YerelKisiData(
      id: data.id.present ? data.id.value : this.id,
      kurumId: data.kurumId.present ? data.kurumId.value : this.kurumId,
      adSoyad: data.adSoyad.present ? data.adSoyad.value : this.adSoyad,
      gorev: data.gorev.present ? data.gorev.value : this.gorev,
      brans: data.brans.present ? data.brans.value : this.brans,
      telefon: data.telefon.present ? data.telefon.value : this.telefon,
    );
  }

  @override
  String toString() {
    return (StringBuffer('YerelKisiData(')
          ..write('id: $id, ')
          ..write('kurumId: $kurumId, ')
          ..write('adSoyad: $adSoyad, ')
          ..write('gorev: $gorev, ')
          ..write('brans: $brans, ')
          ..write('telefon: $telefon')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, kurumId, adSoyad, gorev, brans, telefon);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is YerelKisiData &&
          other.id == this.id &&
          other.kurumId == this.kurumId &&
          other.adSoyad == this.adSoyad &&
          other.gorev == this.gorev &&
          other.brans == this.brans &&
          other.telefon == this.telefon);
}

class YerelKisiCompanion extends UpdateCompanion<YerelKisiData> {
  final Value<String> id;
  final Value<String> kurumId;
  final Value<String> adSoyad;
  final Value<String?> gorev;
  final Value<String?> brans;
  final Value<String?> telefon;
  final Value<int> rowid;
  const YerelKisiCompanion({
    this.id = const Value.absent(),
    this.kurumId = const Value.absent(),
    this.adSoyad = const Value.absent(),
    this.gorev = const Value.absent(),
    this.brans = const Value.absent(),
    this.telefon = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  YerelKisiCompanion.insert({
    required String id,
    required String kurumId,
    required String adSoyad,
    this.gorev = const Value.absent(),
    this.brans = const Value.absent(),
    this.telefon = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kurumId = Value(kurumId),
       adSoyad = Value(adSoyad);
  static Insertable<YerelKisiData> custom({
    Expression<String>? id,
    Expression<String>? kurumId,
    Expression<String>? adSoyad,
    Expression<String>? gorev,
    Expression<String>? brans,
    Expression<String>? telefon,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kurumId != null) 'kurum_id': kurumId,
      if (adSoyad != null) 'ad_soyad': adSoyad,
      if (gorev != null) 'gorev': gorev,
      if (brans != null) 'brans': brans,
      if (telefon != null) 'telefon': telefon,
      if (rowid != null) 'rowid': rowid,
    });
  }

  YerelKisiCompanion copyWith({
    Value<String>? id,
    Value<String>? kurumId,
    Value<String>? adSoyad,
    Value<String?>? gorev,
    Value<String?>? brans,
    Value<String?>? telefon,
    Value<int>? rowid,
  }) {
    return YerelKisiCompanion(
      id: id ?? this.id,
      kurumId: kurumId ?? this.kurumId,
      adSoyad: adSoyad ?? this.adSoyad,
      gorev: gorev ?? this.gorev,
      brans: brans ?? this.brans,
      telefon: telefon ?? this.telefon,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kurumId.present) {
      map['kurum_id'] = Variable<String>(kurumId.value);
    }
    if (adSoyad.present) {
      map['ad_soyad'] = Variable<String>(adSoyad.value);
    }
    if (gorev.present) {
      map['gorev'] = Variable<String>(gorev.value);
    }
    if (brans.present) {
      map['brans'] = Variable<String>(brans.value);
    }
    if (telefon.present) {
      map['telefon'] = Variable<String>(telefon.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('YerelKisiCompanion(')
          ..write('id: $id, ')
          ..write('kurumId: $kurumId, ')
          ..write('adSoyad: $adSoyad, ')
          ..write('gorev: $gorev, ')
          ..write('brans: $brans, ')
          ..write('telefon: $telefon, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $YerelUrunTable extends YerelUrun
    with TableInfo<$YerelUrunTable, YerelUrunData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $YerelUrunTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _adMeta = const VerificationMeta('ad');
  @override
  late final GeneratedColumn<String> ad = GeneratedColumn<String>(
    'ad',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _barkodMeta = const VerificationMeta('barkod');
  @override
  late final GeneratedColumn<String> barkod = GeneratedColumn<String>(
    'barkod',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yayineviMeta = const VerificationMeta(
    'yayinevi',
  );
  @override
  late final GeneratedColumn<String> yayinevi = GeneratedColumn<String>(
    'yayinevi',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kategoriMeta = const VerificationMeta(
    'kategori',
  );
  @override
  late final GeneratedColumn<String> kategori = GeneratedColumn<String>(
    'kategori',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dersMeta = const VerificationMeta('ders');
  @override
  late final GeneratedColumn<String> ders = GeneratedColumn<String>(
    'ders',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _satisFiyatMeta = const VerificationMeta(
    'satisFiyat',
  );
  @override
  late final GeneratedColumn<double> satisFiyat = GeneratedColumn<double>(
    'satis_fiyat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _varsayilanIskontoMeta = const VerificationMeta(
    'varsayilanIskonto',
  );
  @override
  late final GeneratedColumn<double> varsayilanIskonto =
      GeneratedColumn<double>(
        'varsayilan_iskonto',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _stokAdediMeta = const VerificationMeta(
    'stokAdedi',
  );
  @override
  late final GeneratedColumn<int> stokAdedi = GeneratedColumn<int>(
    'stok_adedi',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _aktifMeta = const VerificationMeta('aktif');
  @override
  late final GeneratedColumn<bool> aktif = GeneratedColumn<bool>(
    'aktif',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("aktif" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ad,
    barkod,
    yayinevi,
    kategori,
    ders,
    satisFiyat,
    varsayilanIskonto,
    stokAdedi,
    aktif,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'yerel_urun';
  @override
  VerificationContext validateIntegrity(
    Insertable<YerelUrunData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('ad')) {
      context.handle(_adMeta, ad.isAcceptableOrUnknown(data['ad']!, _adMeta));
    } else if (isInserting) {
      context.missing(_adMeta);
    }
    if (data.containsKey('barkod')) {
      context.handle(
        _barkodMeta,
        barkod.isAcceptableOrUnknown(data['barkod']!, _barkodMeta),
      );
    }
    if (data.containsKey('yayinevi')) {
      context.handle(
        _yayineviMeta,
        yayinevi.isAcceptableOrUnknown(data['yayinevi']!, _yayineviMeta),
      );
    }
    if (data.containsKey('kategori')) {
      context.handle(
        _kategoriMeta,
        kategori.isAcceptableOrUnknown(data['kategori']!, _kategoriMeta),
      );
    }
    if (data.containsKey('ders')) {
      context.handle(
        _dersMeta,
        ders.isAcceptableOrUnknown(data['ders']!, _dersMeta),
      );
    }
    if (data.containsKey('satis_fiyat')) {
      context.handle(
        _satisFiyatMeta,
        satisFiyat.isAcceptableOrUnknown(data['satis_fiyat']!, _satisFiyatMeta),
      );
    }
    if (data.containsKey('varsayilan_iskonto')) {
      context.handle(
        _varsayilanIskontoMeta,
        varsayilanIskonto.isAcceptableOrUnknown(
          data['varsayilan_iskonto']!,
          _varsayilanIskontoMeta,
        ),
      );
    }
    if (data.containsKey('stok_adedi')) {
      context.handle(
        _stokAdediMeta,
        stokAdedi.isAcceptableOrUnknown(data['stok_adedi']!, _stokAdediMeta),
      );
    }
    if (data.containsKey('aktif')) {
      context.handle(
        _aktifMeta,
        aktif.isAcceptableOrUnknown(data['aktif']!, _aktifMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  YerelUrunData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return YerelUrunData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ad: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ad'],
      )!,
      barkod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}barkod'],
      ),
      yayinevi: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}yayinevi'],
      ),
      kategori: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kategori'],
      ),
      ders: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ders'],
      ),
      satisFiyat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}satis_fiyat'],
      ),
      varsayilanIskonto: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}varsayilan_iskonto'],
      )!,
      stokAdedi: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stok_adedi'],
      )!,
      aktif: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}aktif'],
      )!,
    );
  }

  @override
  $YerelUrunTable createAlias(String alias) {
    return $YerelUrunTable(attachedDatabase, alias);
  }
}

class YerelUrunData extends DataClass implements Insertable<YerelUrunData> {
  final String id;
  final String ad;
  final String? barkod;
  final String? yayinevi;
  final String? kategori;
  final String? ders;
  final double? satisFiyat;
  final double varsayilanIskonto;
  final int stokAdedi;
  final bool aktif;
  const YerelUrunData({
    required this.id,
    required this.ad,
    this.barkod,
    this.yayinevi,
    this.kategori,
    this.ders,
    this.satisFiyat,
    required this.varsayilanIskonto,
    required this.stokAdedi,
    required this.aktif,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['ad'] = Variable<String>(ad);
    if (!nullToAbsent || barkod != null) {
      map['barkod'] = Variable<String>(barkod);
    }
    if (!nullToAbsent || yayinevi != null) {
      map['yayinevi'] = Variable<String>(yayinevi);
    }
    if (!nullToAbsent || kategori != null) {
      map['kategori'] = Variable<String>(kategori);
    }
    if (!nullToAbsent || ders != null) {
      map['ders'] = Variable<String>(ders);
    }
    if (!nullToAbsent || satisFiyat != null) {
      map['satis_fiyat'] = Variable<double>(satisFiyat);
    }
    map['varsayilan_iskonto'] = Variable<double>(varsayilanIskonto);
    map['stok_adedi'] = Variable<int>(stokAdedi);
    map['aktif'] = Variable<bool>(aktif);
    return map;
  }

  YerelUrunCompanion toCompanion(bool nullToAbsent) {
    return YerelUrunCompanion(
      id: Value(id),
      ad: Value(ad),
      barkod: barkod == null && nullToAbsent
          ? const Value.absent()
          : Value(barkod),
      yayinevi: yayinevi == null && nullToAbsent
          ? const Value.absent()
          : Value(yayinevi),
      kategori: kategori == null && nullToAbsent
          ? const Value.absent()
          : Value(kategori),
      ders: ders == null && nullToAbsent ? const Value.absent() : Value(ders),
      satisFiyat: satisFiyat == null && nullToAbsent
          ? const Value.absent()
          : Value(satisFiyat),
      varsayilanIskonto: Value(varsayilanIskonto),
      stokAdedi: Value(stokAdedi),
      aktif: Value(aktif),
    );
  }

  factory YerelUrunData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return YerelUrunData(
      id: serializer.fromJson<String>(json['id']),
      ad: serializer.fromJson<String>(json['ad']),
      barkod: serializer.fromJson<String?>(json['barkod']),
      yayinevi: serializer.fromJson<String?>(json['yayinevi']),
      kategori: serializer.fromJson<String?>(json['kategori']),
      ders: serializer.fromJson<String?>(json['ders']),
      satisFiyat: serializer.fromJson<double?>(json['satisFiyat']),
      varsayilanIskonto: serializer.fromJson<double>(json['varsayilanIskonto']),
      stokAdedi: serializer.fromJson<int>(json['stokAdedi']),
      aktif: serializer.fromJson<bool>(json['aktif']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ad': serializer.toJson<String>(ad),
      'barkod': serializer.toJson<String?>(barkod),
      'yayinevi': serializer.toJson<String?>(yayinevi),
      'kategori': serializer.toJson<String?>(kategori),
      'ders': serializer.toJson<String?>(ders),
      'satisFiyat': serializer.toJson<double?>(satisFiyat),
      'varsayilanIskonto': serializer.toJson<double>(varsayilanIskonto),
      'stokAdedi': serializer.toJson<int>(stokAdedi),
      'aktif': serializer.toJson<bool>(aktif),
    };
  }

  YerelUrunData copyWith({
    String? id,
    String? ad,
    Value<String?> barkod = const Value.absent(),
    Value<String?> yayinevi = const Value.absent(),
    Value<String?> kategori = const Value.absent(),
    Value<String?> ders = const Value.absent(),
    Value<double?> satisFiyat = const Value.absent(),
    double? varsayilanIskonto,
    int? stokAdedi,
    bool? aktif,
  }) => YerelUrunData(
    id: id ?? this.id,
    ad: ad ?? this.ad,
    barkod: barkod.present ? barkod.value : this.barkod,
    yayinevi: yayinevi.present ? yayinevi.value : this.yayinevi,
    kategori: kategori.present ? kategori.value : this.kategori,
    ders: ders.present ? ders.value : this.ders,
    satisFiyat: satisFiyat.present ? satisFiyat.value : this.satisFiyat,
    varsayilanIskonto: varsayilanIskonto ?? this.varsayilanIskonto,
    stokAdedi: stokAdedi ?? this.stokAdedi,
    aktif: aktif ?? this.aktif,
  );
  YerelUrunData copyWithCompanion(YerelUrunCompanion data) {
    return YerelUrunData(
      id: data.id.present ? data.id.value : this.id,
      ad: data.ad.present ? data.ad.value : this.ad,
      barkod: data.barkod.present ? data.barkod.value : this.barkod,
      yayinevi: data.yayinevi.present ? data.yayinevi.value : this.yayinevi,
      kategori: data.kategori.present ? data.kategori.value : this.kategori,
      ders: data.ders.present ? data.ders.value : this.ders,
      satisFiyat: data.satisFiyat.present
          ? data.satisFiyat.value
          : this.satisFiyat,
      varsayilanIskonto: data.varsayilanIskonto.present
          ? data.varsayilanIskonto.value
          : this.varsayilanIskonto,
      stokAdedi: data.stokAdedi.present ? data.stokAdedi.value : this.stokAdedi,
      aktif: data.aktif.present ? data.aktif.value : this.aktif,
    );
  }

  @override
  String toString() {
    return (StringBuffer('YerelUrunData(')
          ..write('id: $id, ')
          ..write('ad: $ad, ')
          ..write('barkod: $barkod, ')
          ..write('yayinevi: $yayinevi, ')
          ..write('kategori: $kategori, ')
          ..write('ders: $ders, ')
          ..write('satisFiyat: $satisFiyat, ')
          ..write('varsayilanIskonto: $varsayilanIskonto, ')
          ..write('stokAdedi: $stokAdedi, ')
          ..write('aktif: $aktif')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ad,
    barkod,
    yayinevi,
    kategori,
    ders,
    satisFiyat,
    varsayilanIskonto,
    stokAdedi,
    aktif,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is YerelUrunData &&
          other.id == this.id &&
          other.ad == this.ad &&
          other.barkod == this.barkod &&
          other.yayinevi == this.yayinevi &&
          other.kategori == this.kategori &&
          other.ders == this.ders &&
          other.satisFiyat == this.satisFiyat &&
          other.varsayilanIskonto == this.varsayilanIskonto &&
          other.stokAdedi == this.stokAdedi &&
          other.aktif == this.aktif);
}

class YerelUrunCompanion extends UpdateCompanion<YerelUrunData> {
  final Value<String> id;
  final Value<String> ad;
  final Value<String?> barkod;
  final Value<String?> yayinevi;
  final Value<String?> kategori;
  final Value<String?> ders;
  final Value<double?> satisFiyat;
  final Value<double> varsayilanIskonto;
  final Value<int> stokAdedi;
  final Value<bool> aktif;
  final Value<int> rowid;
  const YerelUrunCompanion({
    this.id = const Value.absent(),
    this.ad = const Value.absent(),
    this.barkod = const Value.absent(),
    this.yayinevi = const Value.absent(),
    this.kategori = const Value.absent(),
    this.ders = const Value.absent(),
    this.satisFiyat = const Value.absent(),
    this.varsayilanIskonto = const Value.absent(),
    this.stokAdedi = const Value.absent(),
    this.aktif = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  YerelUrunCompanion.insert({
    required String id,
    required String ad,
    this.barkod = const Value.absent(),
    this.yayinevi = const Value.absent(),
    this.kategori = const Value.absent(),
    this.ders = const Value.absent(),
    this.satisFiyat = const Value.absent(),
    this.varsayilanIskonto = const Value.absent(),
    this.stokAdedi = const Value.absent(),
    this.aktif = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ad = Value(ad);
  static Insertable<YerelUrunData> custom({
    Expression<String>? id,
    Expression<String>? ad,
    Expression<String>? barkod,
    Expression<String>? yayinevi,
    Expression<String>? kategori,
    Expression<String>? ders,
    Expression<double>? satisFiyat,
    Expression<double>? varsayilanIskonto,
    Expression<int>? stokAdedi,
    Expression<bool>? aktif,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ad != null) 'ad': ad,
      if (barkod != null) 'barkod': barkod,
      if (yayinevi != null) 'yayinevi': yayinevi,
      if (kategori != null) 'kategori': kategori,
      if (ders != null) 'ders': ders,
      if (satisFiyat != null) 'satis_fiyat': satisFiyat,
      if (varsayilanIskonto != null) 'varsayilan_iskonto': varsayilanIskonto,
      if (stokAdedi != null) 'stok_adedi': stokAdedi,
      if (aktif != null) 'aktif': aktif,
      if (rowid != null) 'rowid': rowid,
    });
  }

  YerelUrunCompanion copyWith({
    Value<String>? id,
    Value<String>? ad,
    Value<String?>? barkod,
    Value<String?>? yayinevi,
    Value<String?>? kategori,
    Value<String?>? ders,
    Value<double?>? satisFiyat,
    Value<double>? varsayilanIskonto,
    Value<int>? stokAdedi,
    Value<bool>? aktif,
    Value<int>? rowid,
  }) {
    return YerelUrunCompanion(
      id: id ?? this.id,
      ad: ad ?? this.ad,
      barkod: barkod ?? this.barkod,
      yayinevi: yayinevi ?? this.yayinevi,
      kategori: kategori ?? this.kategori,
      ders: ders ?? this.ders,
      satisFiyat: satisFiyat ?? this.satisFiyat,
      varsayilanIskonto: varsayilanIskonto ?? this.varsayilanIskonto,
      stokAdedi: stokAdedi ?? this.stokAdedi,
      aktif: aktif ?? this.aktif,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ad.present) {
      map['ad'] = Variable<String>(ad.value);
    }
    if (barkod.present) {
      map['barkod'] = Variable<String>(barkod.value);
    }
    if (yayinevi.present) {
      map['yayinevi'] = Variable<String>(yayinevi.value);
    }
    if (kategori.present) {
      map['kategori'] = Variable<String>(kategori.value);
    }
    if (ders.present) {
      map['ders'] = Variable<String>(ders.value);
    }
    if (satisFiyat.present) {
      map['satis_fiyat'] = Variable<double>(satisFiyat.value);
    }
    if (varsayilanIskonto.present) {
      map['varsayilan_iskonto'] = Variable<double>(varsayilanIskonto.value);
    }
    if (stokAdedi.present) {
      map['stok_adedi'] = Variable<int>(stokAdedi.value);
    }
    if (aktif.present) {
      map['aktif'] = Variable<bool>(aktif.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('YerelUrunCompanion(')
          ..write('id: $id, ')
          ..write('ad: $ad, ')
          ..write('barkod: $barkod, ')
          ..write('yayinevi: $yayinevi, ')
          ..write('kategori: $kategori, ')
          ..write('ders: $ders, ')
          ..write('satisFiyat: $satisFiyat, ')
          ..write('varsayilanIskonto: $varsayilanIskonto, ')
          ..write('stokAdedi: $stokAdedi, ')
          ..write('aktif: $aktif, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AyarTable extends Ayar with TableInfo<$AyarTable, AyarData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AyarTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _anahtarMeta = const VerificationMeta(
    'anahtar',
  );
  @override
  late final GeneratedColumn<String> anahtar = GeneratedColumn<String>(
    'anahtar',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _degerMeta = const VerificationMeta('deger');
  @override
  late final GeneratedColumn<String> deger = GeneratedColumn<String>(
    'deger',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [anahtar, deger];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ayar';
  @override
  VerificationContext validateIntegrity(
    Insertable<AyarData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('anahtar')) {
      context.handle(
        _anahtarMeta,
        anahtar.isAcceptableOrUnknown(data['anahtar']!, _anahtarMeta),
      );
    } else if (isInserting) {
      context.missing(_anahtarMeta);
    }
    if (data.containsKey('deger')) {
      context.handle(
        _degerMeta,
        deger.isAcceptableOrUnknown(data['deger']!, _degerMeta),
      );
    } else if (isInserting) {
      context.missing(_degerMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {anahtar};
  @override
  AyarData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AyarData(
      anahtar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}anahtar'],
      )!,
      deger: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deger'],
      )!,
    );
  }

  @override
  $AyarTable createAlias(String alias) {
    return $AyarTable(attachedDatabase, alias);
  }
}

class AyarData extends DataClass implements Insertable<AyarData> {
  final String anahtar;
  final String deger;
  const AyarData({required this.anahtar, required this.deger});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['anahtar'] = Variable<String>(anahtar);
    map['deger'] = Variable<String>(deger);
    return map;
  }

  AyarCompanion toCompanion(bool nullToAbsent) {
    return AyarCompanion(anahtar: Value(anahtar), deger: Value(deger));
  }

  factory AyarData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AyarData(
      anahtar: serializer.fromJson<String>(json['anahtar']),
      deger: serializer.fromJson<String>(json['deger']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'anahtar': serializer.toJson<String>(anahtar),
      'deger': serializer.toJson<String>(deger),
    };
  }

  AyarData copyWith({String? anahtar, String? deger}) =>
      AyarData(anahtar: anahtar ?? this.anahtar, deger: deger ?? this.deger);
  AyarData copyWithCompanion(AyarCompanion data) {
    return AyarData(
      anahtar: data.anahtar.present ? data.anahtar.value : this.anahtar,
      deger: data.deger.present ? data.deger.value : this.deger,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AyarData(')
          ..write('anahtar: $anahtar, ')
          ..write('deger: $deger')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(anahtar, deger);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AyarData &&
          other.anahtar == this.anahtar &&
          other.deger == this.deger);
}

class AyarCompanion extends UpdateCompanion<AyarData> {
  final Value<String> anahtar;
  final Value<String> deger;
  final Value<int> rowid;
  const AyarCompanion({
    this.anahtar = const Value.absent(),
    this.deger = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AyarCompanion.insert({
    required String anahtar,
    required String deger,
    this.rowid = const Value.absent(),
  }) : anahtar = Value(anahtar),
       deger = Value(deger);
  static Insertable<AyarData> custom({
    Expression<String>? anahtar,
    Expression<String>? deger,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (anahtar != null) 'anahtar': anahtar,
      if (deger != null) 'deger': deger,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AyarCompanion copyWith({
    Value<String>? anahtar,
    Value<String>? deger,
    Value<int>? rowid,
  }) {
    return AyarCompanion(
      anahtar: anahtar ?? this.anahtar,
      deger: deger ?? this.deger,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (anahtar.present) {
      map['anahtar'] = Variable<String>(anahtar.value);
    }
    if (deger.present) {
      map['deger'] = Variable<String>(deger.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AyarCompanion(')
          ..write('anahtar: $anahtar, ')
          ..write('deger: $deger, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$YerelDb extends GeneratedDatabase {
  _$YerelDb(QueryExecutor e) : super(e);
  $YerelDbManager get managers => $YerelDbManager(this);
  late final $KuyrukTable kuyruk = $KuyrukTable(this);
  late final $YerelCariTable yerelCari = $YerelCariTable(this);
  late final $YerelKurumTable yerelKurum = $YerelKurumTable(this);
  late final $YerelKisiTable yerelKisi = $YerelKisiTable(this);
  late final $YerelUrunTable yerelUrun = $YerelUrunTable(this);
  late final $AyarTable ayar = $AyarTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    kuyruk,
    yerelCari,
    yerelKurum,
    yerelKisi,
    yerelUrun,
    ayar,
  ];
}

typedef $$KuyrukTableCreateCompanionBuilder =
    KuyrukCompanion Function({
      Value<int> localSeq,
      required String fn,
      required String args,
      Value<String> durum,
      Value<String?> hata,
      required String ozet,
      required DateTime olusturmaLocal,
      Value<int> deneme,
      Value<String?> sonucJson,
    });
typedef $$KuyrukTableUpdateCompanionBuilder =
    KuyrukCompanion Function({
      Value<int> localSeq,
      Value<String> fn,
      Value<String> args,
      Value<String> durum,
      Value<String?> hata,
      Value<String> ozet,
      Value<DateTime> olusturmaLocal,
      Value<int> deneme,
      Value<String?> sonucJson,
    });

class $$KuyrukTableFilterComposer extends Composer<_$YerelDb, $KuyrukTable> {
  $$KuyrukTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fn => $composableBuilder(
    column: $table.fn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get args => $composableBuilder(
    column: $table.args,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get durum => $composableBuilder(
    column: $table.durum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hata => $composableBuilder(
    column: $table.hata,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ozet => $composableBuilder(
    column: $table.ozet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get olusturmaLocal => $composableBuilder(
    column: $table.olusturmaLocal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deneme => $composableBuilder(
    column: $table.deneme,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sonucJson => $composableBuilder(
    column: $table.sonucJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KuyrukTableOrderingComposer extends Composer<_$YerelDb, $KuyrukTable> {
  $$KuyrukTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fn => $composableBuilder(
    column: $table.fn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get args => $composableBuilder(
    column: $table.args,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get durum => $composableBuilder(
    column: $table.durum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hata => $composableBuilder(
    column: $table.hata,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ozet => $composableBuilder(
    column: $table.ozet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get olusturmaLocal => $composableBuilder(
    column: $table.olusturmaLocal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deneme => $composableBuilder(
    column: $table.deneme,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sonucJson => $composableBuilder(
    column: $table.sonucJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KuyrukTableAnnotationComposer
    extends Composer<_$YerelDb, $KuyrukTable> {
  $$KuyrukTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get localSeq =>
      $composableBuilder(column: $table.localSeq, builder: (column) => column);

  GeneratedColumn<String> get fn =>
      $composableBuilder(column: $table.fn, builder: (column) => column);

  GeneratedColumn<String> get args =>
      $composableBuilder(column: $table.args, builder: (column) => column);

  GeneratedColumn<String> get durum =>
      $composableBuilder(column: $table.durum, builder: (column) => column);

  GeneratedColumn<String> get hata =>
      $composableBuilder(column: $table.hata, builder: (column) => column);

  GeneratedColumn<String> get ozet =>
      $composableBuilder(column: $table.ozet, builder: (column) => column);

  GeneratedColumn<DateTime> get olusturmaLocal => $composableBuilder(
    column: $table.olusturmaLocal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deneme =>
      $composableBuilder(column: $table.deneme, builder: (column) => column);

  GeneratedColumn<String> get sonucJson =>
      $composableBuilder(column: $table.sonucJson, builder: (column) => column);
}

class $$KuyrukTableTableManager
    extends
        RootTableManager<
          _$YerelDb,
          $KuyrukTable,
          KuyrukData,
          $$KuyrukTableFilterComposer,
          $$KuyrukTableOrderingComposer,
          $$KuyrukTableAnnotationComposer,
          $$KuyrukTableCreateCompanionBuilder,
          $$KuyrukTableUpdateCompanionBuilder,
          (KuyrukData, BaseReferences<_$YerelDb, $KuyrukTable, KuyrukData>),
          KuyrukData,
          PrefetchHooks Function()
        > {
  $$KuyrukTableTableManager(_$YerelDb db, $KuyrukTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KuyrukTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KuyrukTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KuyrukTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> localSeq = const Value.absent(),
                Value<String> fn = const Value.absent(),
                Value<String> args = const Value.absent(),
                Value<String> durum = const Value.absent(),
                Value<String?> hata = const Value.absent(),
                Value<String> ozet = const Value.absent(),
                Value<DateTime> olusturmaLocal = const Value.absent(),
                Value<int> deneme = const Value.absent(),
                Value<String?> sonucJson = const Value.absent(),
              }) => KuyrukCompanion(
                localSeq: localSeq,
                fn: fn,
                args: args,
                durum: durum,
                hata: hata,
                ozet: ozet,
                olusturmaLocal: olusturmaLocal,
                deneme: deneme,
                sonucJson: sonucJson,
              ),
          createCompanionCallback:
              ({
                Value<int> localSeq = const Value.absent(),
                required String fn,
                required String args,
                Value<String> durum = const Value.absent(),
                Value<String?> hata = const Value.absent(),
                required String ozet,
                required DateTime olusturmaLocal,
                Value<int> deneme = const Value.absent(),
                Value<String?> sonucJson = const Value.absent(),
              }) => KuyrukCompanion.insert(
                localSeq: localSeq,
                fn: fn,
                args: args,
                durum: durum,
                hata: hata,
                ozet: ozet,
                olusturmaLocal: olusturmaLocal,
                deneme: deneme,
                sonucJson: sonucJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KuyrukTableProcessedTableManager =
    ProcessedTableManager<
      _$YerelDb,
      $KuyrukTable,
      KuyrukData,
      $$KuyrukTableFilterComposer,
      $$KuyrukTableOrderingComposer,
      $$KuyrukTableAnnotationComposer,
      $$KuyrukTableCreateCompanionBuilder,
      $$KuyrukTableUpdateCompanionBuilder,
      (KuyrukData, BaseReferences<_$YerelDb, $KuyrukTable, KuyrukData>),
      KuyrukData,
      PrefetchHooks Function()
    >;
typedef $$YerelCariTableCreateCompanionBuilder =
    YerelCariCompanion Function({
      required String id,
      required String unvan,
      required String tip,
      required String durum,
      Value<String?> kurumId,
      Value<double> bakiye,
      Value<double> krediLimiti,
      Value<String?> kademe,
      Value<int> rowid,
    });
typedef $$YerelCariTableUpdateCompanionBuilder =
    YerelCariCompanion Function({
      Value<String> id,
      Value<String> unvan,
      Value<String> tip,
      Value<String> durum,
      Value<String?> kurumId,
      Value<double> bakiye,
      Value<double> krediLimiti,
      Value<String?> kademe,
      Value<int> rowid,
    });

class $$YerelCariTableFilterComposer
    extends Composer<_$YerelDb, $YerelCariTable> {
  $$YerelCariTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unvan => $composableBuilder(
    column: $table.unvan,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tip => $composableBuilder(
    column: $table.tip,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get durum => $composableBuilder(
    column: $table.durum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kurumId => $composableBuilder(
    column: $table.kurumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bakiye => $composableBuilder(
    column: $table.bakiye,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get krediLimiti => $composableBuilder(
    column: $table.krediLimiti,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kademe => $composableBuilder(
    column: $table.kademe,
    builder: (column) => ColumnFilters(column),
  );
}

class $$YerelCariTableOrderingComposer
    extends Composer<_$YerelDb, $YerelCariTable> {
  $$YerelCariTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unvan => $composableBuilder(
    column: $table.unvan,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tip => $composableBuilder(
    column: $table.tip,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get durum => $composableBuilder(
    column: $table.durum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kurumId => $composableBuilder(
    column: $table.kurumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bakiye => $composableBuilder(
    column: $table.bakiye,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get krediLimiti => $composableBuilder(
    column: $table.krediLimiti,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kademe => $composableBuilder(
    column: $table.kademe,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$YerelCariTableAnnotationComposer
    extends Composer<_$YerelDb, $YerelCariTable> {
  $$YerelCariTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get unvan =>
      $composableBuilder(column: $table.unvan, builder: (column) => column);

  GeneratedColumn<String> get tip =>
      $composableBuilder(column: $table.tip, builder: (column) => column);

  GeneratedColumn<String> get durum =>
      $composableBuilder(column: $table.durum, builder: (column) => column);

  GeneratedColumn<String> get kurumId =>
      $composableBuilder(column: $table.kurumId, builder: (column) => column);

  GeneratedColumn<double> get bakiye =>
      $composableBuilder(column: $table.bakiye, builder: (column) => column);

  GeneratedColumn<double> get krediLimiti => $composableBuilder(
    column: $table.krediLimiti,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kademe =>
      $composableBuilder(column: $table.kademe, builder: (column) => column);
}

class $$YerelCariTableTableManager
    extends
        RootTableManager<
          _$YerelDb,
          $YerelCariTable,
          YerelCariData,
          $$YerelCariTableFilterComposer,
          $$YerelCariTableOrderingComposer,
          $$YerelCariTableAnnotationComposer,
          $$YerelCariTableCreateCompanionBuilder,
          $$YerelCariTableUpdateCompanionBuilder,
          (
            YerelCariData,
            BaseReferences<_$YerelDb, $YerelCariTable, YerelCariData>,
          ),
          YerelCariData,
          PrefetchHooks Function()
        > {
  $$YerelCariTableTableManager(_$YerelDb db, $YerelCariTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$YerelCariTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$YerelCariTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$YerelCariTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> unvan = const Value.absent(),
                Value<String> tip = const Value.absent(),
                Value<String> durum = const Value.absent(),
                Value<String?> kurumId = const Value.absent(),
                Value<double> bakiye = const Value.absent(),
                Value<double> krediLimiti = const Value.absent(),
                Value<String?> kademe = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => YerelCariCompanion(
                id: id,
                unvan: unvan,
                tip: tip,
                durum: durum,
                kurumId: kurumId,
                bakiye: bakiye,
                krediLimiti: krediLimiti,
                kademe: kademe,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String unvan,
                required String tip,
                required String durum,
                Value<String?> kurumId = const Value.absent(),
                Value<double> bakiye = const Value.absent(),
                Value<double> krediLimiti = const Value.absent(),
                Value<String?> kademe = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => YerelCariCompanion.insert(
                id: id,
                unvan: unvan,
                tip: tip,
                durum: durum,
                kurumId: kurumId,
                bakiye: bakiye,
                krediLimiti: krediLimiti,
                kademe: kademe,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$YerelCariTableProcessedTableManager =
    ProcessedTableManager<
      _$YerelDb,
      $YerelCariTable,
      YerelCariData,
      $$YerelCariTableFilterComposer,
      $$YerelCariTableOrderingComposer,
      $$YerelCariTableAnnotationComposer,
      $$YerelCariTableCreateCompanionBuilder,
      $$YerelCariTableUpdateCompanionBuilder,
      (
        YerelCariData,
        BaseReferences<_$YerelDb, $YerelCariTable, YerelCariData>,
      ),
      YerelCariData,
      PrefetchHooks Function()
    >;
typedef $$YerelKurumTableCreateCompanionBuilder =
    YerelKurumCompanion Function({
      required String id,
      required String ad,
      Value<String?> il,
      Value<String?> ilce,
      Value<String?> tip,
      Value<int> rowid,
    });
typedef $$YerelKurumTableUpdateCompanionBuilder =
    YerelKurumCompanion Function({
      Value<String> id,
      Value<String> ad,
      Value<String?> il,
      Value<String?> ilce,
      Value<String?> tip,
      Value<int> rowid,
    });

class $$YerelKurumTableFilterComposer
    extends Composer<_$YerelDb, $YerelKurumTable> {
  $$YerelKurumTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ad => $composableBuilder(
    column: $table.ad,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get il => $composableBuilder(
    column: $table.il,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ilce => $composableBuilder(
    column: $table.ilce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tip => $composableBuilder(
    column: $table.tip,
    builder: (column) => ColumnFilters(column),
  );
}

class $$YerelKurumTableOrderingComposer
    extends Composer<_$YerelDb, $YerelKurumTable> {
  $$YerelKurumTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ad => $composableBuilder(
    column: $table.ad,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get il => $composableBuilder(
    column: $table.il,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ilce => $composableBuilder(
    column: $table.ilce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tip => $composableBuilder(
    column: $table.tip,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$YerelKurumTableAnnotationComposer
    extends Composer<_$YerelDb, $YerelKurumTable> {
  $$YerelKurumTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ad =>
      $composableBuilder(column: $table.ad, builder: (column) => column);

  GeneratedColumn<String> get il =>
      $composableBuilder(column: $table.il, builder: (column) => column);

  GeneratedColumn<String> get ilce =>
      $composableBuilder(column: $table.ilce, builder: (column) => column);

  GeneratedColumn<String> get tip =>
      $composableBuilder(column: $table.tip, builder: (column) => column);
}

class $$YerelKurumTableTableManager
    extends
        RootTableManager<
          _$YerelDb,
          $YerelKurumTable,
          YerelKurumData,
          $$YerelKurumTableFilterComposer,
          $$YerelKurumTableOrderingComposer,
          $$YerelKurumTableAnnotationComposer,
          $$YerelKurumTableCreateCompanionBuilder,
          $$YerelKurumTableUpdateCompanionBuilder,
          (
            YerelKurumData,
            BaseReferences<_$YerelDb, $YerelKurumTable, YerelKurumData>,
          ),
          YerelKurumData,
          PrefetchHooks Function()
        > {
  $$YerelKurumTableTableManager(_$YerelDb db, $YerelKurumTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$YerelKurumTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$YerelKurumTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$YerelKurumTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ad = const Value.absent(),
                Value<String?> il = const Value.absent(),
                Value<String?> ilce = const Value.absent(),
                Value<String?> tip = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => YerelKurumCompanion(
                id: id,
                ad: ad,
                il: il,
                ilce: ilce,
                tip: tip,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ad,
                Value<String?> il = const Value.absent(),
                Value<String?> ilce = const Value.absent(),
                Value<String?> tip = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => YerelKurumCompanion.insert(
                id: id,
                ad: ad,
                il: il,
                ilce: ilce,
                tip: tip,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$YerelKurumTableProcessedTableManager =
    ProcessedTableManager<
      _$YerelDb,
      $YerelKurumTable,
      YerelKurumData,
      $$YerelKurumTableFilterComposer,
      $$YerelKurumTableOrderingComposer,
      $$YerelKurumTableAnnotationComposer,
      $$YerelKurumTableCreateCompanionBuilder,
      $$YerelKurumTableUpdateCompanionBuilder,
      (
        YerelKurumData,
        BaseReferences<_$YerelDb, $YerelKurumTable, YerelKurumData>,
      ),
      YerelKurumData,
      PrefetchHooks Function()
    >;
typedef $$YerelKisiTableCreateCompanionBuilder =
    YerelKisiCompanion Function({
      required String id,
      required String kurumId,
      required String adSoyad,
      Value<String?> gorev,
      Value<String?> brans,
      Value<String?> telefon,
      Value<int> rowid,
    });
typedef $$YerelKisiTableUpdateCompanionBuilder =
    YerelKisiCompanion Function({
      Value<String> id,
      Value<String> kurumId,
      Value<String> adSoyad,
      Value<String?> gorev,
      Value<String?> brans,
      Value<String?> telefon,
      Value<int> rowid,
    });

class $$YerelKisiTableFilterComposer
    extends Composer<_$YerelDb, $YerelKisiTable> {
  $$YerelKisiTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kurumId => $composableBuilder(
    column: $table.kurumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get adSoyad => $composableBuilder(
    column: $table.adSoyad,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gorev => $composableBuilder(
    column: $table.gorev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brans => $composableBuilder(
    column: $table.brans,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get telefon => $composableBuilder(
    column: $table.telefon,
    builder: (column) => ColumnFilters(column),
  );
}

class $$YerelKisiTableOrderingComposer
    extends Composer<_$YerelDb, $YerelKisiTable> {
  $$YerelKisiTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kurumId => $composableBuilder(
    column: $table.kurumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get adSoyad => $composableBuilder(
    column: $table.adSoyad,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gorev => $composableBuilder(
    column: $table.gorev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brans => $composableBuilder(
    column: $table.brans,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get telefon => $composableBuilder(
    column: $table.telefon,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$YerelKisiTableAnnotationComposer
    extends Composer<_$YerelDb, $YerelKisiTable> {
  $$YerelKisiTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kurumId =>
      $composableBuilder(column: $table.kurumId, builder: (column) => column);

  GeneratedColumn<String> get adSoyad =>
      $composableBuilder(column: $table.adSoyad, builder: (column) => column);

  GeneratedColumn<String> get gorev =>
      $composableBuilder(column: $table.gorev, builder: (column) => column);

  GeneratedColumn<String> get brans =>
      $composableBuilder(column: $table.brans, builder: (column) => column);

  GeneratedColumn<String> get telefon =>
      $composableBuilder(column: $table.telefon, builder: (column) => column);
}

class $$YerelKisiTableTableManager
    extends
        RootTableManager<
          _$YerelDb,
          $YerelKisiTable,
          YerelKisiData,
          $$YerelKisiTableFilterComposer,
          $$YerelKisiTableOrderingComposer,
          $$YerelKisiTableAnnotationComposer,
          $$YerelKisiTableCreateCompanionBuilder,
          $$YerelKisiTableUpdateCompanionBuilder,
          (
            YerelKisiData,
            BaseReferences<_$YerelDb, $YerelKisiTable, YerelKisiData>,
          ),
          YerelKisiData,
          PrefetchHooks Function()
        > {
  $$YerelKisiTableTableManager(_$YerelDb db, $YerelKisiTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$YerelKisiTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$YerelKisiTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$YerelKisiTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kurumId = const Value.absent(),
                Value<String> adSoyad = const Value.absent(),
                Value<String?> gorev = const Value.absent(),
                Value<String?> brans = const Value.absent(),
                Value<String?> telefon = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => YerelKisiCompanion(
                id: id,
                kurumId: kurumId,
                adSoyad: adSoyad,
                gorev: gorev,
                brans: brans,
                telefon: telefon,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kurumId,
                required String adSoyad,
                Value<String?> gorev = const Value.absent(),
                Value<String?> brans = const Value.absent(),
                Value<String?> telefon = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => YerelKisiCompanion.insert(
                id: id,
                kurumId: kurumId,
                adSoyad: adSoyad,
                gorev: gorev,
                brans: brans,
                telefon: telefon,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$YerelKisiTableProcessedTableManager =
    ProcessedTableManager<
      _$YerelDb,
      $YerelKisiTable,
      YerelKisiData,
      $$YerelKisiTableFilterComposer,
      $$YerelKisiTableOrderingComposer,
      $$YerelKisiTableAnnotationComposer,
      $$YerelKisiTableCreateCompanionBuilder,
      $$YerelKisiTableUpdateCompanionBuilder,
      (
        YerelKisiData,
        BaseReferences<_$YerelDb, $YerelKisiTable, YerelKisiData>,
      ),
      YerelKisiData,
      PrefetchHooks Function()
    >;
typedef $$YerelUrunTableCreateCompanionBuilder =
    YerelUrunCompanion Function({
      required String id,
      required String ad,
      Value<String?> barkod,
      Value<String?> yayinevi,
      Value<String?> kategori,
      Value<String?> ders,
      Value<double?> satisFiyat,
      Value<double> varsayilanIskonto,
      Value<int> stokAdedi,
      Value<bool> aktif,
      Value<int> rowid,
    });
typedef $$YerelUrunTableUpdateCompanionBuilder =
    YerelUrunCompanion Function({
      Value<String> id,
      Value<String> ad,
      Value<String?> barkod,
      Value<String?> yayinevi,
      Value<String?> kategori,
      Value<String?> ders,
      Value<double?> satisFiyat,
      Value<double> varsayilanIskonto,
      Value<int> stokAdedi,
      Value<bool> aktif,
      Value<int> rowid,
    });

class $$YerelUrunTableFilterComposer
    extends Composer<_$YerelDb, $YerelUrunTable> {
  $$YerelUrunTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ad => $composableBuilder(
    column: $table.ad,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get barkod => $composableBuilder(
    column: $table.barkod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get yayinevi => $composableBuilder(
    column: $table.yayinevi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kategori => $composableBuilder(
    column: $table.kategori,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ders => $composableBuilder(
    column: $table.ders,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get satisFiyat => $composableBuilder(
    column: $table.satisFiyat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get varsayilanIskonto => $composableBuilder(
    column: $table.varsayilanIskonto,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stokAdedi => $composableBuilder(
    column: $table.stokAdedi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get aktif => $composableBuilder(
    column: $table.aktif,
    builder: (column) => ColumnFilters(column),
  );
}

class $$YerelUrunTableOrderingComposer
    extends Composer<_$YerelDb, $YerelUrunTable> {
  $$YerelUrunTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ad => $composableBuilder(
    column: $table.ad,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get barkod => $composableBuilder(
    column: $table.barkod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get yayinevi => $composableBuilder(
    column: $table.yayinevi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kategori => $composableBuilder(
    column: $table.kategori,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ders => $composableBuilder(
    column: $table.ders,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get satisFiyat => $composableBuilder(
    column: $table.satisFiyat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get varsayilanIskonto => $composableBuilder(
    column: $table.varsayilanIskonto,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stokAdedi => $composableBuilder(
    column: $table.stokAdedi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get aktif => $composableBuilder(
    column: $table.aktif,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$YerelUrunTableAnnotationComposer
    extends Composer<_$YerelDb, $YerelUrunTable> {
  $$YerelUrunTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ad =>
      $composableBuilder(column: $table.ad, builder: (column) => column);

  GeneratedColumn<String> get barkod =>
      $composableBuilder(column: $table.barkod, builder: (column) => column);

  GeneratedColumn<String> get yayinevi =>
      $composableBuilder(column: $table.yayinevi, builder: (column) => column);

  GeneratedColumn<String> get kategori =>
      $composableBuilder(column: $table.kategori, builder: (column) => column);

  GeneratedColumn<String> get ders =>
      $composableBuilder(column: $table.ders, builder: (column) => column);

  GeneratedColumn<double> get satisFiyat => $composableBuilder(
    column: $table.satisFiyat,
    builder: (column) => column,
  );

  GeneratedColumn<double> get varsayilanIskonto => $composableBuilder(
    column: $table.varsayilanIskonto,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stokAdedi =>
      $composableBuilder(column: $table.stokAdedi, builder: (column) => column);

  GeneratedColumn<bool> get aktif =>
      $composableBuilder(column: $table.aktif, builder: (column) => column);
}

class $$YerelUrunTableTableManager
    extends
        RootTableManager<
          _$YerelDb,
          $YerelUrunTable,
          YerelUrunData,
          $$YerelUrunTableFilterComposer,
          $$YerelUrunTableOrderingComposer,
          $$YerelUrunTableAnnotationComposer,
          $$YerelUrunTableCreateCompanionBuilder,
          $$YerelUrunTableUpdateCompanionBuilder,
          (
            YerelUrunData,
            BaseReferences<_$YerelDb, $YerelUrunTable, YerelUrunData>,
          ),
          YerelUrunData,
          PrefetchHooks Function()
        > {
  $$YerelUrunTableTableManager(_$YerelDb db, $YerelUrunTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$YerelUrunTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$YerelUrunTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$YerelUrunTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ad = const Value.absent(),
                Value<String?> barkod = const Value.absent(),
                Value<String?> yayinevi = const Value.absent(),
                Value<String?> kategori = const Value.absent(),
                Value<String?> ders = const Value.absent(),
                Value<double?> satisFiyat = const Value.absent(),
                Value<double> varsayilanIskonto = const Value.absent(),
                Value<int> stokAdedi = const Value.absent(),
                Value<bool> aktif = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => YerelUrunCompanion(
                id: id,
                ad: ad,
                barkod: barkod,
                yayinevi: yayinevi,
                kategori: kategori,
                ders: ders,
                satisFiyat: satisFiyat,
                varsayilanIskonto: varsayilanIskonto,
                stokAdedi: stokAdedi,
                aktif: aktif,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ad,
                Value<String?> barkod = const Value.absent(),
                Value<String?> yayinevi = const Value.absent(),
                Value<String?> kategori = const Value.absent(),
                Value<String?> ders = const Value.absent(),
                Value<double?> satisFiyat = const Value.absent(),
                Value<double> varsayilanIskonto = const Value.absent(),
                Value<int> stokAdedi = const Value.absent(),
                Value<bool> aktif = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => YerelUrunCompanion.insert(
                id: id,
                ad: ad,
                barkod: barkod,
                yayinevi: yayinevi,
                kategori: kategori,
                ders: ders,
                satisFiyat: satisFiyat,
                varsayilanIskonto: varsayilanIskonto,
                stokAdedi: stokAdedi,
                aktif: aktif,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$YerelUrunTableProcessedTableManager =
    ProcessedTableManager<
      _$YerelDb,
      $YerelUrunTable,
      YerelUrunData,
      $$YerelUrunTableFilterComposer,
      $$YerelUrunTableOrderingComposer,
      $$YerelUrunTableAnnotationComposer,
      $$YerelUrunTableCreateCompanionBuilder,
      $$YerelUrunTableUpdateCompanionBuilder,
      (
        YerelUrunData,
        BaseReferences<_$YerelDb, $YerelUrunTable, YerelUrunData>,
      ),
      YerelUrunData,
      PrefetchHooks Function()
    >;
typedef $$AyarTableCreateCompanionBuilder =
    AyarCompanion Function({
      required String anahtar,
      required String deger,
      Value<int> rowid,
    });
typedef $$AyarTableUpdateCompanionBuilder =
    AyarCompanion Function({
      Value<String> anahtar,
      Value<String> deger,
      Value<int> rowid,
    });

class $$AyarTableFilterComposer extends Composer<_$YerelDb, $AyarTable> {
  $$AyarTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get anahtar => $composableBuilder(
    column: $table.anahtar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deger => $composableBuilder(
    column: $table.deger,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AyarTableOrderingComposer extends Composer<_$YerelDb, $AyarTable> {
  $$AyarTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get anahtar => $composableBuilder(
    column: $table.anahtar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deger => $composableBuilder(
    column: $table.deger,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AyarTableAnnotationComposer extends Composer<_$YerelDb, $AyarTable> {
  $$AyarTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get anahtar =>
      $composableBuilder(column: $table.anahtar, builder: (column) => column);

  GeneratedColumn<String> get deger =>
      $composableBuilder(column: $table.deger, builder: (column) => column);
}

class $$AyarTableTableManager
    extends
        RootTableManager<
          _$YerelDb,
          $AyarTable,
          AyarData,
          $$AyarTableFilterComposer,
          $$AyarTableOrderingComposer,
          $$AyarTableAnnotationComposer,
          $$AyarTableCreateCompanionBuilder,
          $$AyarTableUpdateCompanionBuilder,
          (AyarData, BaseReferences<_$YerelDb, $AyarTable, AyarData>),
          AyarData,
          PrefetchHooks Function()
        > {
  $$AyarTableTableManager(_$YerelDb db, $AyarTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AyarTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AyarTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AyarTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> anahtar = const Value.absent(),
                Value<String> deger = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AyarCompanion(anahtar: anahtar, deger: deger, rowid: rowid),
          createCompanionCallback:
              ({
                required String anahtar,
                required String deger,
                Value<int> rowid = const Value.absent(),
              }) => AyarCompanion.insert(
                anahtar: anahtar,
                deger: deger,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AyarTableProcessedTableManager =
    ProcessedTableManager<
      _$YerelDb,
      $AyarTable,
      AyarData,
      $$AyarTableFilterComposer,
      $$AyarTableOrderingComposer,
      $$AyarTableAnnotationComposer,
      $$AyarTableCreateCompanionBuilder,
      $$AyarTableUpdateCompanionBuilder,
      (AyarData, BaseReferences<_$YerelDb, $AyarTable, AyarData>),
      AyarData,
      PrefetchHooks Function()
    >;

class $YerelDbManager {
  final _$YerelDb _db;
  $YerelDbManager(this._db);
  $$KuyrukTableTableManager get kuyruk =>
      $$KuyrukTableTableManager(_db, _db.kuyruk);
  $$YerelCariTableTableManager get yerelCari =>
      $$YerelCariTableTableManager(_db, _db.yerelCari);
  $$YerelKurumTableTableManager get yerelKurum =>
      $$YerelKurumTableTableManager(_db, _db.yerelKurum);
  $$YerelKisiTableTableManager get yerelKisi =>
      $$YerelKisiTableTableManager(_db, _db.yerelKisi);
  $$YerelUrunTableTableManager get yerelUrun =>
      $$YerelUrunTableTableManager(_db, _db.yerelUrun);
  $$AyarTableTableManager get ayar => $$AyarTableTableManager(_db, _db.ayar);
}
