{ stdenvNoCC, fetchFromGitHub, lib, lua }:

let
  luaEnv = lua.withPackages (p: [ p.lua-zlib p.http ]);
in

stdenvNoCC.mkDerivation {
  name = "mpv-bilibili-chat";
  src = ./.;
  dontBuild = true;
  postPatch = ''
    sed -i '/@path@/s|^-- ||;s|@path@|${lua.pkgs.luaLib.genLuaPathAbsStr luaEnv}|' bilibili-chat.lua
    sed -i '/@cpath@/s|^-- ||;s|@cpath@|${lua.pkgs.luaLib.genLuaCPathAbsStr luaEnv}|' bilibili-chat.lua
  '';
  installPhase = ''
    runHook preInstall
    install -Dm444 bilibili-chat.lua -t $out/share/mpv/scripts/
    runHook postInstall
  '';
  passthru.scriptName = "bilibili-chat.lua";

  meta = {
    description = "Mpv script that overlays bilibili live chat messages on top of the livestream";
    homepage = "https://github.com/chuangzhu/mpv-bilibili-chat";
    maintainers = [ lib.maintainers.chuangzhu ];
    license = lib.licenses.mit;
  };
}
