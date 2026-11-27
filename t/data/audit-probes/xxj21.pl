my %h = (a=>1,b=>2,c=>3); my $n = 0; while (my ($k,$v) = each %h) { $n += $v } print "$n\n";
