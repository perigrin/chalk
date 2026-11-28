my %h = (a=>1); my $s = "$h{a}-@h{'a'}-$h{'a'}"; print "$s\n";
