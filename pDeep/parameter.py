class pDeepParameter:
    def __init__(self, cfg = None):
        self._ion_types = ['b{}', 'y{}', 'b{}-ModLoss', 'y{}-ModLoss'] # ion order for pDeep model, do not change this
        self._max_ion_charge = 2 # ion charge = 1 or 2 for pDeep model
        self._ion_terms = {'a{}': 'n', 'x{}': 'c', 'b{}': 'n', 'y{}': 'c', 'c{}': 'n', 'z{}': 'c', 'b{}-ModLoss': 'n', 'y{}-ModLoss': 'c', 'b{}-H2O': 'n', 'y{}-H2O': 'c', 'b{}-NH3': 'n', 'y{}-NH3': 'c'}
        for iontype, term in list(self._ion_terms.items()):
            self._ion_terms[iontype.format("")] = term
        self._ion_type_idx = {}
        for i in range(len(self._ion_types)):
            self._ion_type_idx[self._ion_types[i]] = i
            self._ion_type_idx[self._ion_types[i].format('')] = i
            
        ######################################################################
        
        self.library_ion_types = self._ion_types
    
        self.model = "tmp/model/pretrain-180921-modloss-mod8D.ckpt"
        self.RT_model = "tmp/model/RT_model.ckpt"
        
        self._pDeepModel = None
        self._pDeepRT = None
        
        self.threads = 4
        self.predict_batch = 4096
        
        self.fixmod = ["Carbamidomethyl[C]"]
        self.varmod = "Acetyl[ProteinN-term],Oxidation[M],Phospho[Y],Phospho[S],Phospho[T]".split(",")
        self.min_varmod = 0
        self.max_varmod = 3

        self.predict_input = "none"
        self.predict_instrument = "QE"
        self.predict_nce = 27
        self.predict_output = "none"

        # tune parameters:
        self.tune_psmlabels = []
        self.tune_RT_psmlabel = ""
        self.epochs = 2
        self.n_tune_per_psmlabel = 1000
        self.tune_batch = 1024
        
        self.test_psmlabels = []
        self.test_RT_psmlabel = ""
        self.n_test_per_psmlabel = 100000000

        self.fasta = None

        if cfg: self._read_cfg(cfg)

    def GetPredictedIonTypeIndices(self, ion_types):
        return [self._ion_type_idx[iontype]*self._max_ion_charge+ch for iontype in ion_types for ch in range(self._max_ion_charge)]
    
    def _read_cfg(self, cfg):
        with open(cfg) as f:
            lines = f.readlines()

            def parse_folder(line):
                items = line.split("=")[1].split("|")
                items[0] = items[0].strip()  # folder
                items[1] = items[1].strip()  # instrument
                items[2] = int(items[2].strip())  # NCE
                if len(items) >= 4: items[3] = items[3].strip()
                return items

            def get_int(line):
                return int(get_str(line))

            def get_str(line):
                return line[line.find("=")+1:].strip()

            for i in range(len(lines)):
                line = lines[i].strip()
                if line.startswith("model"):
                    self.model = get_str(line)
                elif line.startswith("RT_model"):
                    self.RT_model = get_str(line)
                elif line.startswith("threads"):
                    self.threads = get_int(line)
                elif line.startswith("predict_batch"):
                    self.predict_batch = get_int(line)
                    
                elif line.startswith("mod_no_check"):
                    self.fixmod = get_str(line).strip(",").split(",")
                elif line.startswith("mod_check"):
                    self.varmod = get_str(line).strip(",").split(",")
                elif line.startswith("min_mod_check"):
                    self.min_varmod = get_int(line)
                elif line.startswith("max_mod_check"):
                    self.max_varmod = get_int(line)

                elif line.startswith("predict_input"):
                    self.predict_input, self.predict_instrument, self.predict_nce = parse_folder(line)[:3]
                    self.predict_nce = int(self.predict_nce)
                elif line.startswith("predict_output"):
                    self.predict_output = get_str(line)
                elif line.startswith("fasta"):
                    self.fasta = get_str(line)

                # tune_parameters
                elif line.startswith("tune_psmlabels"):
                    line = get_str(line)
                    if line: self.tune_psmlabels = [s.strip() for s in line.split("|")]
                elif line.startswith("tune_epochs"):
                    self.epochs = get_int(line)
                elif line.startswith("tune_batch"):
                    self.train_batch = get_int(line)
                elif line.startswith("n_tune_per_psmlabel"):
                    self.n_tune_per_psmlabel = get_int(line)
                elif line.startswith("tune_RT_psmlabel"):
                    self.tune_RT_psmlabel = get_str(line)
                    
                elif line.startswith("test_psmlabels"):
                    line = get_str(line)
                    if line: self.test_psmlabels = [s.strip() for s in line.split("|")]
                elif line.startswith("test_RT_psmlabel"):
                    self.test_RT_psmlabel = get_str(line)
                elif line.startswith("n_test_per_psmlabel"):
                    self.n_test_per_psmlabel = get_int(line)
