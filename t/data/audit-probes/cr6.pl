my $o = {}; my $was = ref($o) eq "HASH" ? "plain" : "obj"; bless $o, "K"; my $is = ref($o) eq "HASH" ? "plain" : "obj"; print "$was $is\n";
