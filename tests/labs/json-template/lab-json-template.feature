Feature: AI-Fillable Lab & Genetics JSON Template Export and Idempotent Re-Ingestion

  As the owner digitizing multi-page bloodwork and DNA PDF reports with an AI agent
  I want to export a self-documenting JSON template listing every draw prep field, marker ID, allowed unit, specimen/assay option, and genotype option, and re-import the AI-filled JSON
  So an AI agent can populate dozens of markers, <LOD values, blood pressure pairs, qualitative results, and genotypes accurately in one shot without manual typing or duplicate rows.

  Scenario: Exporting template JSON includes all draw prep fields, marker definitions, units, assays, and genes, and re-importing filled JSON creates/updates draws and genotypes idempotently
    Given a LabCatalogue with quantitative markers, <LOD hs-CRP, paired Blood Pressure, qualitative urinalysis, and genes
    When LabJsonTemplateService exports a blank template JSON
    Then the JSON contains draw metadata/prep fields, marker_guide entries with allowed_units and default_unit, and gene_guide entries with allowed_genotypes and custom_genotype support
    When an AI agent fills a draw with numeric, <LOD, paired BP, qualitative text, custom unit multiplier, and genotypes and LabJsonTemplateService imports it twice
    Then the first import adds 1 draw, all results, and genotypes, and the second import updates in place with 0 duplicate draws or results
