my %h = (k => "ab"); $_ .= "c" for @h{qw(k)}; print "$h{k}\n";
