sealed class IrType {
  const IrType();
}

final class IrString extends IrType {
  const IrString();
}

final class IrInt extends IrType {
  const IrInt();
}

final class IrDouble extends IrType {
  const IrDouble();
}

final class IrBool extends IrType {
  const IrBool();
}

final class IrJson extends IrType {
  const IrJson();
}

final class IrStringMap extends IrType {
  const IrStringMap();
}

final class IrJsonMap extends IrType {
  const IrJsonMap();
}

final class IrList extends IrType {
  const IrList(this.element);
  final IrType element;
}

final class IrRef extends IrType {
  const IrRef(this.className);
  final String className;
}

final class IrEnumRef extends IrType {
  const IrEnumRef(this.enumName);
  final String enumName;
}

final class IrUnionRef extends IrType {
  const IrUnionRef(this.unionName);
  final String unionName;
}

enum DateKind { none, unixSecondsString, isoString }

enum ClassKind { model, params }

final class FieldIr {
  const FieldIr({
    required this.wireName,
    required this.dartName,
    required this.type,
    required this.required,
    this.docs,
    this.deprecated = false,
    this.deprecationMessage,
    this.dateKind = DateKind.none,
    this.isId = false,
    this.requiredInSpec = false,
  });

  final String wireName;
  final String dartName;
  final IrType type;
  final bool required;
  final String? docs;
  final bool deprecated;
  final String? deprecationMessage;
  final DateKind dateKind;
  final bool isId;
  final bool requiredInSpec;
}

final class ClassIr {
  ClassIr({
    required this.className,
    required this.kind,
    required this.fields,
    this.docs,
    this.superType,
    this.origin,
  });

  final String className;
  final ClassKind kind;
  final List<FieldIr> fields;
  final String? docs;
  String? superType;
  final String? origin;
}

final class EnumValueIr {
  const EnumValueIr(
      {required this.wire, required this.dartName, this.deprecated = false});
  final String wire;
  final String dartName;
  final bool deprecated;
}

final class EnumIr {
  const EnumIr({required this.enumName, required this.values, this.docs});
  final String enumName;
  final List<EnumValueIr> values;
  final String? docs;
}

final class UnionVariantIr {
  const UnionVariantIr({required this.wireValue, required this.className});
  final String wireValue;
  final String className;
}

final class UnionIr {
  UnionIr(
      {required this.unionName,
      required this.discriminator,
      required this.variants,
      this.docs,
      this.superType});
  final String unionName;
  final String discriminator;
  final List<UnionVariantIr> variants;
  final String? docs;
  String? superType;
}

enum PageKind { base, cursor, withTimeframe, withTotal }

sealed class ResponseIr {
  const ResponseIr();
}

final class VoidResponse extends ResponseIr {
  const VoidResponse();
}

final class UnwrapResponse extends ResponseIr {
  const UnwrapResponse(this.type);
  final IrType type;
}

final class EnvelopeResponse extends ResponseIr {
  const EnvelopeResponse(this.className);
  final String className;
}

final class PageResponse extends ResponseIr {
  const PageResponse(this.kind, this.itemType);
  final PageKind kind;
  final IrType itemType;
}

final class TextResponse extends ResponseIr {
  const TextResponse();
}

final class BytesResponse extends ResponseIr {
  const BytesResponse();
}

final class ParamIr {
  const ParamIr({
    required this.wireName,
    required this.dartName,
    required this.type,
    required this.required,
    this.docs,
    this.enumValues,
  });
  final String wireName;
  final String dartName;
  final IrType type;
  final bool required;
  final String? docs;
  final List<String>? enumValues;
}

final class OperationIr {
  const OperationIr({
    required this.namespacePath,
    required this.methodName,
    required this.httpMethod,
    required this.pathTemplate,
    required this.pathParams,
    required this.queryParams,
    required this.bodyClass,
    required this.response,
    required this.host,
    required this.accept,
    this.docs,
    this.deprecated = false,
    this.deprecationMessage,
  });

  final List<String> namespacePath;
  final String methodName;
  final String httpMethod;
  final String pathTemplate;
  final List<ParamIr> pathParams;
  final List<ParamIr> queryParams;
  final String? bodyClass;
  final ResponseIr response;
  final String host;
  final String accept;
  final String? docs;
  final bool deprecated;
  final String? deprecationMessage;
}

final class NamespaceIr {
  NamespaceIr({required this.path, required this.className});
  final List<String> path;
  final String className;
  final Map<String, NamespaceIr> children = {};
  final List<OperationIr> operations = [];
}

final class WebhookIr {
  const WebhookIr(
      {required this.eventType,
      required this.className,
      required this.dataType,
      this.docs});
  final String eventType;
  final String className;
  final IrType? dataType;
  final String? docs;
}

final class GeneratorIr {
  const GeneratorIr({
    required this.classes,
    required this.enums,
    required this.unions,
    required this.namespaces,
    required this.webhooks,
    required this.examples,
  });

  final Map<String, ClassIr> classes;
  final Map<String, EnumIr> enums;
  final Map<String, UnionIr> unions;
  final Map<String, NamespaceIr> namespaces;
  final List<WebhookIr> webhooks;
  final Map<String, List<Map<String, Object?>>> examples;
}
