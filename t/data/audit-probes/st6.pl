my $o = bless {}, "A"; my $a = ref($o); my $q = $o; bless $q, "B"; print "$a ", ref($o), "\n";
