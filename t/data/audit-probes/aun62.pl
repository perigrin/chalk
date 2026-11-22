my $o = bless {}, "A"; my $was = $o->isa("A") ? 1:0; bless $o, "B"; my $is = $o->isa("A") ? 1:0; print "$was $is\n";
