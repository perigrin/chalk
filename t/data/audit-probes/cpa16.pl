my %h=(k=>[1]); my %c=%h; push $c{k}->@*, 2; $c{n}=1; print scalar($h{k}->@*), " ", (exists $h{n} ? "y" : "n"), "\n";
