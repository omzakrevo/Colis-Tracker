import { Router, type IRouter } from "express";
import healthRouter from "./health";
import authRouter from "./auth";
import usersRouter from "./users";
import garesRouter from "./gares";
import colisRouter from "./colis";
import historiqueRouter from "./historique";
import rapportsRouter from "./rapports";
import settingsRouter from "./settings";

const router: IRouter = Router();

router.use(healthRouter);
router.use(authRouter);
router.use(usersRouter);
router.use(garesRouter);
router.use(colisRouter);
router.use(historiqueRouter);
router.use(rapportsRouter);
router.use(settingsRouter);

export default router;
