my @a = (1, 2); sub f { my @t = map { $_ + 1 } @_; "@t" } my @l = map { f($_, $_) } @a; print "@l\n";
