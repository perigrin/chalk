# ABOUTME: Facade for standard IR optimization pipeline
# ABOUTME: Per Chapter 18: IterPeeps (Opto) -> DCE -> GCM (Schedule)

use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Optimizer {
    use Chalk::IR::OptimizerPipeline;
    use Chalk::IR::Optimizer::IterPeeps;
    use Chalk::IR::Optimizer::DCE;
    use Chalk::IR::Optimizer::GCM;

    # Class method for simple optimization call
    # Usage: my $optimized = Chalk::IR::Optimizer->optimize($graph);
    sub optimize($class, $graph) {
        my $pipeline = Chalk::IR::OptimizerPipeline->new(
            optimizers => [
                # Per Chapter 18 CodeGen driver phases:
                # 1. Opto: "General optimizations; iterate peepholes"
                Chalk::IR::Optimizer::IterPeeps->new(),
                # 2. DCE: Dead code elimination
                Chalk::IR::Optimizer::DCE->new(),
                # 3. Schedule: "Global Code Motion"
                Chalk::IR::Optimizer::GCM->new(),
            ]
        );
        return $pipeline->apply($graph);
    }

    # Instance method for pipeline compatibility
    method apply($graph) {
        return __CLASS__->optimize($graph);
    }
}

1;
