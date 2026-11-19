my %h = (a=>1,b=>2,c=>3); my ($k1) = each %h; keys %h; my ($k2) = each %h; print(($k1 eq $k2 ? "same" : "diff"), "\n");
