my %h = (a=>1,b=>2); my @x = each %h; keys %h; my @y = each %h; print $x[0] eq $y[0] ? "reset" : "no", "\n";
