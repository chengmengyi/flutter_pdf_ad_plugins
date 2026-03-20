enum AdPlacement {
  prNewLaunch,
  prLaunch,
  prPermissionOpen,
  prNewNat,
  prNewLanNat,
  prNewGuideNat1,
  prNewGuideNat2,
  prNewGuideNat3,
  prBan4,
  prNat1,
  prNat2,
  prNat3,
  prTab,
  prMainTools,
  prTabTools,
  prAiTool,
  prExit,
}

extension AdPlacementX on AdPlacement {
  String get jsonKey {
    switch (this) {
      case AdPlacement.prNewLaunch:
        return 'pr_new_launch';
      case AdPlacement.prLaunch:
        return 'pr_launch';
      case AdPlacement.prPermissionOpen:
        return 'pr_permission_open';
      case AdPlacement.prNewNat:
        return 'pr_new_nat';
      case AdPlacement.prNewLanNat:
        return 'pr_new_lan_nat';
      case AdPlacement.prNewGuideNat1:
        return 'pr_new_guide_nat1';
      case AdPlacement.prNewGuideNat2:
        return 'pr_new_guide_nat2';
      case AdPlacement.prNewGuideNat3:
        return 'pr_new_guide_nat3';
      case AdPlacement.prBan4:
        return 'pr_ban4';
      case AdPlacement.prNat1:
        return 'pr_nat1';
      case AdPlacement.prNat2:
        return 'pr_nat2';
      case AdPlacement.prNat3:
        return 'pr_nat3';
      case AdPlacement.prTab:
        return 'pr_tab';
      case AdPlacement.prMainTools:
        return 'pr_main_tools';
      case AdPlacement.prTabTools:
        return 'pr_tab_tools';
      case AdPlacement.prAiTool:
        return 'pr_ai_tool';
      case AdPlacement.prExit:
        return 'pr_exit';
    }
  }

  static AdPlacement? tryParse(String rawValue) {
    for (final placement in AdPlacement.values) {
      if (placement.jsonKey == rawValue) {
        return placement;
      }
    }
    return null;
  }
}
