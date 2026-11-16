Name:       harbour-meteoradar
Version:    0.1.0
Release:    1
Summary:    Precipitation radar map for Sailfish OS (Meteor-style)
License:    MIT
BuildArch:  noarch
Source0:    %{name}-%{version}.tar.gz

Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   libsailfishapp-launcher
Requires:   qt5-qtdeclarative-import-positioning
Requires:   qt5-qtgraphicaleffects
Requires:   nemo-qml-plugin-configuration-qt5
Requires:   nemo-qml-plugin-dbus-qt5

%description
Meteoradar shows precipitation measured by the Czech Hydrometeorological
Institute (CHMU) weather radar on a map, with animation of past frames and
a short nowcast, optional lightning layer, selectable base map and a
home-screen cover with the latest radar frame.

%prep
%setup -q

%build
# nothing to build, pure QML

%install
rm -rf %{buildroot}
install -d %{buildroot}%{_datadir}/%{name}/qml/pages
install -d %{buildroot}%{_datadir}/%{name}/qml/cover
install -d %{buildroot}%{_datadir}/%{name}/qml/components
install -d %{buildroot}%{_datadir}/%{name}/qml/js
install -m 644 qml/%{name}.qml %{buildroot}%{_datadir}/%{name}/qml/
install -m 644 qml/pages/*.qml %{buildroot}%{_datadir}/%{name}/qml/pages/
install -m 644 qml/cover/*.qml %{buildroot}%{_datadir}/%{name}/qml/cover/
install -m 644 qml/components/*.qml %{buildroot}%{_datadir}/%{name}/qml/components/
install -m 644 qml/js/*.js %{buildroot}%{_datadir}/%{name}/qml/js/
install -d %{buildroot}%{_datadir}/applications
install -m 644 %{name}.desktop %{buildroot}%{_datadir}/applications/
for s in 86 108 128 172; do
    install -d %{buildroot}%{_datadir}/icons/hicolor/${s}x${s}/apps
    install -m 644 icons/${s}x${s}/%{name}.png %{buildroot}%{_datadir}/icons/hicolor/${s}x${s}/apps/
done

%files
%defattr(-,root,root,-)
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png

%changelog
* Mon Nov 09 2026 mig - 0.1.0-1
- Initial release
