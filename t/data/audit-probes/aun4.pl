our %h=(a=>0); sub bump { $h{a} += 10 } for (1..3) { $h{a}++; bump() } print "$h{a}\n";
