# Citation audit
Automated verification of `paper/references.bib`, produced by `scripts/verify_references.py`.
Every entry's DOI is resolved against **Crossref** (articles and proceedings) or **DataCite** (Zenodo software records), and every `eprint` id against the **arXiv API**. The returned title, first-author surname and year are compared against what the `.bib` file claims. Re-run the script to reproduce this table.
- Entries: **38** (verified 36, needs review 2, unresolved 0)

Status meanings:
- **VERIFIED** — every resolved record agrees with the bib entry on title, first author and year.
- **REVIEW** — the record resolved but at least one field disagrees. Usually LaTeX braces or punctuation in the title; read the note and confirm by eye.
- **UNRESOLVED** — no DOI and no arXiv id to check against, or the registry had no record. These need a manual link.
- Entries with incomplete metadata: **0**

| # | Key | Cited as (title) | Type | Identifier | Verified link | Registry | Status | Metadata | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `chen2018neural` | Neural Ordinary Differential Equations | inproceedings | `10.48550/arXiv.1806.07366` | [resolve](https://doi.org/10.48550/arXiv.1806.07366) | DataCite, arXiv | **VERIFIED** | complete | — |
| 2 | `rackauckas2020universal` | Universal Differential Equations for Scientific Machine Learning | article | `10.48550/arXiv.2001.04385` | [resolve](https://doi.org/10.48550/arXiv.2001.04385) | DataCite, arXiv | **VERIFIED** | complete | — |
| 3 | `raissi2019pinn` | Physics-informed neural networks: A deep learning framework for solving forwa... | article | `10.1016/j.jcp.2018.10.045` | [resolve](https://doi.org/10.1016/j.jcp.2018.10.045) | Crossref | **VERIFIED** | complete | — |
| 4 | `silvestri2023analysis` | An Analysis of Universal Differential Equations for Data-Driven Discovery of ... | inproceedings | `10.1007/978-3-031-36027-5_27` | [resolve](https://doi.org/10.1007/978-3-031-36027-5_27) | Crossref, arXiv | **VERIFIED** | complete | — |
| 5 | `philipps2025ude` | Current state and open problems in universal differential equations for syste... | article | `10.1038/s41540-025-00550-w` | [resolve](https://doi.org/10.1038/s41540-025-00550-w) | Crossref | **VERIFIED** | complete | — |
| 6 | `brunton2016sindy` | Discovering governing equations from data by sparse identification of nonline... | article | `10.1073/pnas.1517384113` | [resolve](https://doi.org/10.1073/pnas.1517384113) | Crossref | **VERIFIED** | complete | — |
| 7 | `zheng2019sr3` | A Unified Framework for Sparse Relaxed Regularized Regression: {SR3} | article | `10.1109/ACCESS.2018.2886528` | [resolve](https://doi.org/10.1109/ACCESS.2018.2886528) | Crossref, arXiv | **VERIFIED** | complete | — |
| 8 | `rudy2017pdefind` | Data-driven discovery of partial differential equations | article | `10.1126/sciadv.1602614` | [resolve](https://doi.org/10.1126/sciadv.1602614) | Crossref | **VERIFIED** | complete | — |
| 9 | `fasel2022ensemblesindy` | Ensemble-{SINDy}: Robust sparse model discovery in the low-data, high-noise l... | article | `10.1098/rspa.2021.0904` | [resolve](https://doi.org/10.1098/rspa.2021.0904) | Crossref | **VERIFIED** | complete | — |
| 10 | `desilva2020pysindy` | {PySINDy}: A Python package for the sparse identification of nonlinear dynami... | article | `10.21105/joss.02104` | [resolve](https://doi.org/10.21105/joss.02104) | Crossref | **VERIFIED** | complete | — |
| 11 | `udrescu2020aifeynman` | {AI Feynman}: A physics-inspired method for symbolic regression | article | `10.1126/sciadv.aay2631` | [resolve](https://doi.org/10.1126/sciadv.aay2631) | Crossref | **VERIFIED** | complete | — |
| 12 | `cranmer2023pysr` | Interpretable Machine Learning for Science with {PySR} and {SymbolicRegressio... | article | `10.48550/arXiv.2305.01582` | [resolve](https://doi.org/10.48550/arXiv.2305.01582) | DataCite, arXiv | **VERIFIED** | complete | — |
| 13 | `hodgkin1952` | A quantitative description of membrane current and its application to conduct... | article | `10.1113/jphysiol.1952.sp004764` | [resolve](https://doi.org/10.1113/jphysiol.1952.sp004764) | Crossref | **VERIFIED** | complete | — |
| 14 | `pospischil2008` | Minimal {Hodgkin--Huxley} type models for different classes of cortical and t... | article | `10.1007/s00422-008-0263-8` | [resolve](https://doi.org/10.1007/s00422-008-0263-8) | Crossref | **VERIFIED** | complete | — |
| 15 | `reuveni1993` | Stepwise repolarization from {Ca$^{2+}$} plateaus in neocortical pyramidal ce... | article | `10.1523/JNEUROSCI.13-11-04609.1993` | [resolve](https://doi.org/10.1523/JNEUROSCI.13-11-04609.1993) | Crossref | **VERIFIED** | complete | — |
| 16 | `golomb1997` | Propagating neuronal discharges in neocortical slices: computational and expe... | article | `10.1152/jn.1997.78.3.1199` | [resolve](https://doi.org/10.1152/jn.1997.78.3.1199) | Crossref | **VERIFIED** | complete | — |
| 17 | `magistretti1999` | Biophysical Properties and Slow Voltage-Dependent Inactivation of a Sustained... | article | `10.1085/jgp.114.4.491` | [resolve](https://doi.org/10.1085/jgp.114.4.491) | Crossref | **VERIFIED** | complete | — |
| 18 | `prinz2004` | Similar network activity from disparate circuit parameters | article | `10.1038/nn1352` | [resolve](https://doi.org/10.1038/nn1352) | Crossref | **VERIFIED** | complete | — |
| 19 | `marder2011` | Multiple models to capture the variability in biological neurons and networks | article | `10.1038/nn.2735` | [resolve](https://doi.org/10.1038/nn.2735) | Crossref | **VERIFIED** | complete | — |
| 20 | `golowasch2002` | Failure of averaging in the construction of a conductance-based neuron model | article | `10.1152/jn.00412.2001` | [resolve](https://doi.org/10.1152/jn.00412.2001) | Crossref | **VERIFIED** | complete | — |
| 21 | `ori2018` | Cellular function given parametric variation in the {Hodgkin} and {Huxley} mo... | article | `10.1073/pnas.1808552115` | [resolve](https://doi.org/10.1073/pnas.1808552115) | Crossref | **VERIFIED** | complete | — |
| 22 | `walch2016` | Parameter identifiability and identifiable combinations in generalized {Hodgk... | article | `10.1016/j.neucom.2016.03.027` | [resolve](https://doi.org/10.1016/j.neucom.2016.03.027) | Crossref, arXiv | **VERIFIED** | complete | — |
| 23 | `daly2015` | {Hodgkin--Huxley} revisited: reparametrization and identifiability analysis o... | article | `10.1098/rsos.150499` | [resolve](https://doi.org/10.1098/rsos.150499) | Crossref | **VERIFIED** | complete | — |
| 24 | `raue2009` | Structural and practical identifiability analysis of partially observed dynam... | article | `10.1093/bioinformatics/btp358` | [resolve](https://doi.org/10.1093/bioinformatics/btp358) | Crossref | **VERIFIED** | complete | — |
| 25 | `wieland2021` | On structural and practical identifiability | article | `10.1016/j.coisb.2021.03.005` | [resolve](https://doi.org/10.1016/j.coisb.2021.03.005) | Crossref, arXiv | **VERIFIED** | complete | — |
| 26 | `loman2026structural` | Structural functional identifiability and model discovery in differential equ... | article | `10.48550/arXiv.2606.30289` | [resolve](https://doi.org/10.48550/arXiv.2606.30289) | DataCite, arXiv | **VERIFIED** | complete | — |
| 27 | `loman2025ude` | Functional and parametric identifiability for universal differential equation... | article | `10.48550/arXiv.2510.14140` | [resolve](https://doi.org/10.48550/arXiv.2510.14140) | DataCite, arXiv | **VERIFIED** | complete | — |
| 28 | `norden2025structural` | On the importance of structural identifiability for machine learning with par... | article | `10.48550/arXiv.2502.04131` | [resolve](https://doi.org/10.48550/arXiv.2502.04131) | DataCite, arXiv | **VERIFIED** | complete | — |
| 29 | `beck2026hybrid` | Learning Hybrid Biophysical Neuron Models with Neural {ODEs} | article | `10.48550/arXiv.2606.16693` | [resolve](https://doi.org/10.48550/arXiv.2606.16693) | DataCite, arXiv | **VERIFIED** | complete | — |
| 30 | `kainth2025pinodesr` | Physics-Informed Neural {ODEs} with Scale-Aware Residuals for Learning Stiff ... | article | `10.48550/arXiv.2511.11734` | [resolve](https://doi.org/10.48550/arXiv.2511.11734) | DataCite, arXiv | **VERIFIED** | complete | — |
| 31 | `elgazzar2025ude` | Universal differential equations as a unifying modeling language for neurosci... | article | `10.3389/fncom.2025.1677930` | [resolve](https://doi.org/10.3389/fncom.2025.1677930) | Crossref | **VERIFIED** | complete | — |
| 32 | `burghi2021feedback` | Feedback identification of conductance-based models | article | `10.1016/j.automatica.2020.109297` | [resolve](https://doi.org/10.1016/j.automatica.2020.109297) | Crossref, arXiv | **VERIFIED** | complete | — |
| 33 | `meliza2014` | Estimating parameters and predicting membrane voltages with conductance-based... | article | `10.1007/s00422-014-0615-5` | [resolve](https://doi.org/10.1007/s00422-014-0615-5) | Crossref | **VERIFIED** | complete | — |
| 34 | `iravanian2020` | Discovery of the Hidden State in Ionic Models Using a Domain-Specific Recurre... | article | `10.48550/arXiv.2011.07388` | [resolve](https://doi.org/10.48550/arXiv.2011.07388) | DataCite, arXiv | **VERIFIED** | complete | — |
| 35 | `rackauckas2017diffeq` | {DifferentialEquations.jl} -- A Performant and Feature-Rich Ecosystem for Sol... | article | `10.5334/jors.151` | [resolve](https://doi.org/10.5334/jors.151) | Crossref | **VERIFIED** | complete | — |
| 36 | `ma2021comparison` | A Comparison of Automatic Differentiation and Continuous Sensitivity Analysis... | inproceedings | `10.1109/HPEC49654.2021.9622796` | [resolve](https://doi.org/10.1109/HPEC49654.2021.9622796) | Crossref, arXiv | **REVIEW** | complete | arXiv year 2018 vs bib 2021 |
| 37 | `pal2023lux` | {Lux: Explicit Parameterization of Deep Neural Networks in Julia} | software | `10.5281/zenodo.7808903` | [resolve](https://doi.org/10.5281/zenodo.7808903) | DataCite | **REVIEW** | complete | DataCite year 2026 vs bib 2023 |
| 38 | `dixit2023optimization` | {Optimization.jl}: A Unified Optimization Package | software | `10.5281/zenodo.7738524` | [resolve](https://doi.org/10.5281/zenodo.7738524) | DataCite | **VERIFIED** | complete | — |

## Cross-check against the manuscript

- Entries in the bib file: **38**
- Distinct keys cited in `paper/main.tex`: **38**
- Bib entries never cited: **none**
- Cited keys with no bib entry: **none**
