class AdInfoBean {
  AdInfoBean({
      this.adId, 
      this.adPlat, 
      this.exportTime, 
      this.sort, 
      this.userGroup,});

  AdInfoBean.fromJson(dynamic json) {
    adId = json['adId'];
    adPlat = json['adPlat'];
    exportTime = json['exportTime'];
    sort = json['sort'];
    userGroup = json['userGroup'] != null ? json['userGroup'].cast<int>() : [];
  }
  String? adId;
  String? adPlat;
  int? exportTime;
  int? sort;
  List<int>? userGroup;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['adId'] = adId;
    map['adPlat'] = adPlat;
    map['exportTime'] = exportTime;
    map['sort'] = sort;
    map['userGroup'] = userGroup;
    return map;
  }

}