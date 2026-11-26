#!/usr/bin/perl
# 建置映像時修改網頁編輯器的 bundle.js（見 Dockerfile）。每一項都要剛好找到一處，找不到或找到多處時
# 結束碼非 0、建置失敗：升版後上游改了寫法會發現，不會悄悄沒改到。
#
# bundle.js 的長字串會以「反斜線＋換行」斷行（例如網址被斷成 ...plugins/g\<換行>itiles...），
# 斷行位置隨版本改變，所以比對時允許任兩個字元之間有這個斷行。
use strict;
use warnings;

my $file = shift or die "用法：patch-bundle.pl <bundle.js>\n";
open my $in, '<:raw', $file or die "讀不到 $file：$!\n";
my $js = do { local $/; <$in> };
close $in;

# 字面字串轉成允許「反斜線＋換行」斷在任兩個字元之間的正規式
sub wrapped {
    my ($text) = @_;
    return join '(?:\\\\\n)?', map { quotemeta } split //, $text;
}

# 把 $re 換成 $repl（可用 $1 等），必須剛好一處
sub replace_once {
    my ($name, $re, $repl) = @_;
    my $count = () = $js =~ /$re/g;
    die "$name：找到 $count 處（應為 1 處），上游可能改了寫法\n" unless $count == 1;
    $js =~ s/$re/$repl->()/e;
    print "已修改：$name\n";
}

# 1. 關於對話框的 git hash 連結：上游連到 Collabora 的 gerrit，改連本 repo 的 Release（映像的建置腳本與對應原始碼）。
#    顯示的 hash 仍是上游 online 的 commit
my $gerrit = wrapped('https://gerrit.collaboraoffice.com/plugins/gitiles/online/+log/');
replace_once(
    'git hash 連結改連 GitHub Release',
    qr/$gerrit\$\{(\w+)\.coolwsdHash\}/,
    sub { 'https://github.com/TSAA-T300/online-editor/releases' },
);

# 2. 關於對話框的著作權：上游是「Copyright © 年, 廠商.」，廠商設成 ITRI 時讀起來像整個程式屬於 ITRI。
#    寫明 ITRI 只有修改部分，程式本體的著作權屬於 Collabora Online 與 LibreOffice 的貢獻者
my $copyright = wrapped('Copyright © ${') . '(\w+)' . wrapped('.copyrightYear}, ${') . '\w+' . wrapped('.vendor}.');
replace_once(
    '著作權寫明修改部分與上游',
    qr/$copyright/,
    sub { 'Copyright © ${' . $1 . '.copyrightYear}, ITRI (modifications). Based on Collabora Online and LibreOffice, © their respective contributors.' },
);

# 3. 新手導覽（26.04 新增）不自動跳出：大部分內容沒有繁中翻譯。上游沒有關閉的設定（ui_defaults 只接受白名單的鍵），
#    改成一律視為「已看過」。說明選單的「導覽」仍可手動開啟
replace_once(
    '新手導覽不自動跳出',
    qr/getBooleanDocTypePref\("onboardingTourSeen",!1\)/,
    sub { 'getBooleanDocTypePref("onboardingTourSeen",!1)||!0' },
);

open my $out, '>:raw', $file or die "寫不進 $file：$!\n";
print $out $js;
close $out;
