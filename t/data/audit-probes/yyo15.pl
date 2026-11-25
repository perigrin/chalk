use List::Util qw(sum max min first reduce uniq); print sum(1..4), max(3,9,2), min(3,9,2), (first { $_ > 2 } 1..5), (reduce { $a * $b } 1..5), scalar(uniq(1,1,2)), "\n";
