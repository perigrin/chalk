sub cls { ref($_[0]) } my $o = bless {}, "A"; my $a = cls($o); bless $o, "B"; print "$a ", cls($o), "\n";
