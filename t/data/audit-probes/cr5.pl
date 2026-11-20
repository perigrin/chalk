sub re { bless $_[0], $_[1]; return } my $o = bless [], "A"; my $a = ref($o); re($o, "B"); my $b = ref($o); re($o, "C"); print "$a $b ", ref($o), "\n";
