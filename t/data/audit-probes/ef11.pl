package K; sub hi { "hi" } package main; my $h = {}; my $o = bless $h, "K"; print $h->hi, "\n";
