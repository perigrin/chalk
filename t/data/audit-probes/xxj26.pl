my %h = (a=>1,b=>2); my @v = values %h; $_++ for @v; my $t = 0; $t += $_ for values %h; print "$t\n";
