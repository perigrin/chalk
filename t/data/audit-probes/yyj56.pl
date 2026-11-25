my @r = map { [$_, map { $_ * 2 } 1..$_] } 1..2; print join("|", map { "@$_" } @r), "\n";
