sub mk { return bless {}, "A" } sub re { bless $_[0], "B"; return } my $o = mk(); my $a = ref($o); re($o); print "$a ", ref($o), "\n";
