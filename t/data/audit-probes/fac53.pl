my %h=(a=>1); my %c=(%h); my %d=(x=>0,%h); $h{a}=2; print "$c{a}$d{a}\n";
