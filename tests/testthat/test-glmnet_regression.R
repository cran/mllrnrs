library(mlbench)
data("BostonHousing")
dataset <- BostonHousing |>
  data.table::as.data.table() |>
  na.omit()

seed <- 312
feature_cols <- colnames(dataset)[1:13]

param_list_glmnet <- expand.grid(
  alpha = seq(0, 1, 0.05)
)

if (isTRUE(as.logical(Sys.getenv("_R_CHECK_LIMIT_CORES_")))) {
  # on cran
  ncores <- 2L
} else {
  ncores <- ifelse(
    test = parallel::detectCores() > 4,
    yes = 4L,
    no = ifelse(
      test = parallel::detectCores() < 2L,
      yes = 1L,
      no = parallel::detectCores()
    )
  )
}

train_x <- model.matrix(
  ~ -1 + .,
  dataset[, .SD, .SDcols = feature_cols]
)
train_y <- log(dataset[, get("medv")])

options("mlexperiments.bayesian.max_init" = 10L)

fold_list <- splitTools::create_folds(
  y = train_y,
  k = 3,
  type = "stratified",
  seed = seed
)

# ###########################################################################
# %% TUNING
# ###########################################################################

glmnet_bounds <- list(
  alpha = c(0., 1.)
)
optim_args <- list(
  iters.n = ncores,
  kappa = 3.5,
  acq = "ucb"
)

# ###########################################################################
# %% NESTED CV
# ###########################################################################

test_that(
  desc = "test nested cv, bayesian, regression - glmnet",
  code = {

    glmnet_optimizer <- mlexperiments::MLNestedCV$new(
      learner = mllrnrs::LearnerGlmnet$new(
        metric_optimization_higher_better = FALSE
      ),
      strategy = "bayesian",
      fold_list = fold_list,
      k_tuning = 3L,
      ncores = ncores,
      seed = seed
    )

    glmnet_optimizer$parameter_bounds <- glmnet_bounds
    glmnet_optimizer$parameter_grid <- param_list_glmnet
    glmnet_optimizer$split_type <- "stratified"
    glmnet_optimizer$optim_args <- optim_args

    glmnet_optimizer$learner_args <- list(
      family = "gaussian",
      type.measure = "mse",
      standardize = TRUE
    )
    glmnet_optimizer$predict_args <- list(type = "response")
    glmnet_optimizer$performance_metric <- mlexperiments::metric("rmsle")

    # set data
    glmnet_optimizer$set_data(
      x = train_x,
      y = train_y
    )

    cv_results <- glmnet_optimizer$execute()
    expect_type(cv_results, "list")
    expect_equal(dim(cv_results), c(3, 7))
    expect_true(inherits(
      x = glmnet_optimizer$results,
      what = "mlexCV"
    ))
  }
)


test_that(
  desc = "test nested cv, grid - glmnet",
  code = {

    glmnet_optimizer <- mlexperiments::MLNestedCV$new(
      learner = mllrnrs::LearnerGlmnet$new(
        metric_optimization_higher_better = FALSE
      ),
      strategy = "grid",
      fold_list = fold_list,
      k_tuning = 3L,
      ncores = ncores,
      seed = seed
    )
    set.seed(seed)
    random_grid <- sample(seq_len(nrow(param_list_glmnet)), 3)
    glmnet_optimizer$parameter_grid <- kdry::mlh_subset(
      param_list_glmnet,
      random_grid
    )
    glmnet_optimizer$split_type <- "stratified"

    glmnet_optimizer$learner_args <- list(
      family = "gaussian",
      type.measure = "mse",
      standardize = TRUE
    )
    glmnet_optimizer$predict_args <- list(type = "response")
    glmnet_optimizer$performance_metric <- mlexperiments::metric("rmsle")

    # set data
    glmnet_optimizer$set_data(
      x = train_x,
      y = train_y
    )

    cv_results <- glmnet_optimizer$execute()
    expect_type(cv_results, "list")
    expect_equal(dim(cv_results), c(3, 7))
    expect_true(inherits(
      x = glmnet_optimizer$results,
      what = "mlexCV"
    ))
  }
)
