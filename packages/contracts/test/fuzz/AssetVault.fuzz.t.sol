// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";
import {AssetVault} from "../../src/AssetVault.sol";
import {IAssetVault} from "../../src/interfaces/IAssetVault.sol";
import {ComplianceConstants} from "../../src/libraries/ComplianceConstants.sol";

/// @title AssetVaultFuzz
/// @notice Fuzz tests (>=10k runs) para las propiedades de matemática y fund-flow de AssetVault:
///         el split reserva-técnica / monto-neto en `comprar`, y el reembolso proporcional en
///         `reembolsarLoteFallido`.
/// @dev Las propiedades se derivan EXACTAMENTE de las fórmulas en src/AssetVault.sol y
///      src/libraries/QualityRules.sol (no se adivinan):
///        - reservaRetenida = montoUSDC * reservaBps / 10_000  (división entera, floor)
///        - montoNeto       = montoUSDC - reservaRetenida
///        - reembolso(buyer) = totalDisponible * balance(buyer) / totalSupply  (floor)
abstract contract AssetVaultFuzzBase is BaseTest {
    // Lote auxiliar para fuzz — IDs distintos de LOTE_ID_DEFAULT para no chocar con helpers de BaseTest.
    uint256 internal constant FUZZ_LOTE_ID = 7;

    /// @dev Crea un lote de fuzz con parámetros controlables (kg, precio, reservaBps).
    function _crearLoteFuzz(uint256 loteId, uint256 kgEsperados, uint256 precioPorTokenUSDC, uint16 reservaBps)
        internal
    {
        vm.prank(ADMIN_OPERATOR);
        assetVault.crearLote(
            loteId,
            kgEsperados,
            precioPorTokenUSDC,
            uint64(block.timestamp + 90 days),
            ORIGEN_BOLIVIA,
            TREASURY_SRL,
            keccak256("FSA-FUZZ"),
            reservaBps,
            VARIEDAD_ROMERO
        );
    }

    /// @dev Compra `cantidadTokens` para `buyer` en `loteId` pagando exactamente `montoUSDC`.
    ///      Asume buyer ya tiene KYC. Funda el contrato con el USDC del pago (modelo escrow total).
    function _comprarFuzz(uint256 loteId, address buyer, uint256 cantidadTokens, uint256 montoUSDC) internal {
        usdc.mint(address(assetVault), montoUSDC);
        vm.prank(BACKEND_SIGNER);
        assetVault.comprar(loteId, cantidadTokens, buyer, montoUSDC, keccak256("payment"));
    }
}

contract AssetVaultFuzz is AssetVaultFuzzBase {
    // ============================================================================
    // comprar — split reserva técnica vs monto neto
    // ============================================================================

    /// @dev Propiedad central de `comprar` (fórmula en QualityRules.calcularReservaTecnica):
    ///        reservaRetenida = montoUSDC * reservaBps / 10_000
    ///        montoNeto       = montoUSDC - reservaRetenida
    ///      Por lo tanto SIEMPRE: reservaTecnicaUSDC + montoNetoPendiente == montoUSDCPagado (sin pérdida),
    ///      y reservaTecnicaUSDC == montoUSDCPagado * reservaBps / 10_000 exacto.
    ///      Además verifica que el mint actualiza balance/supply y que no hay overflow.
    function testFuzz_comprar_ReservaMasNetoIgualMontoYBalances(
        uint256 cantidadTokens,
        uint256 precioPorTokenUSDC,
        uint16 reservaBps,
        uint256 montoExtra
    ) public {
        // Bound de inputs a rangos válidos del contrato.
        // reservaBps ∈ [MIN, MAX] (1500..2000), exigido por crearLote.
        reservaBps = uint16(
            bound(reservaBps, ComplianceConstants.RESERVA_TECNICA_BPS_MIN, ComplianceConstants.RESERVA_TECNICA_BPS_MAX)
        );

        // cantidadTokens ∈ [1, 200] — kgEsperados=100 ⇒ cap en gramos = 100*1000/500 = 200 tokens.
        cantidadTokens = bound(cantidadTokens, 1, 200);

        // precio acotado para evitar montos absurdos pero cubriendo un rango amplio (1 wei..1M USDC/token).
        precioPorTokenUSDC = bound(precioPorTokenUSDC, 1, 1_000_000 * 1e6);

        // El comprador puede sobrepagar; montoExtra ∈ [0, 1M USDC]. montoUSDC = montoEsperado + extra.
        montoExtra = bound(montoExtra, 0, 1_000_000 * 1e6);
        uint256 montoEsperado = cantidadTokens * precioPorTokenUSDC;
        uint256 montoUSDC = montoEsperado + montoExtra;

        // Arrange
        _crearLoteFuzz(FUZZ_LOTE_ID, 100, precioPorTokenUSDC, reservaBps);
        _setupKYC(BUYER_1, 1);

        uint256 supplyBefore = assetVault.totalSupply(FUZZ_LOTE_ID);
        uint256 balanceBefore = assetVault.balanceOf(BUYER_1, FUZZ_LOTE_ID);

        // Act
        _comprarFuzz(FUZZ_LOTE_ID, BUYER_1, cantidadTokens, montoUSDC);

        // Assert — fórmula exacta del contrato.
        IAssetVault.LoteMiel memory lote = assetVault.lotes(FUZZ_LOTE_ID);
        uint256 reservaEsperada = (montoUSDC * reservaBps) / ComplianceConstants.BPS_DENOMINATOR;
        uint256 netoEsperado = montoUSDC - reservaEsperada;

        assertEq(lote.reservaTecnicaUSDC, reservaEsperada, "reserva debe ser montoUSDC*bps/10000 (floor)");
        assertEq(lote.montoNetoPendiente, netoEsperado, "montoNeto debe ser montoUSDC - reserva");

        // Conservación: reserva + neto == monto pagado (el split nunca crea ni destruye USDC).
        assertEq(
            lote.reservaTecnicaUSDC + lote.montoNetoPendiente,
            montoUSDC,
            "reserva + neto debe igualar exactamente el monto pagado"
        );

        // La reserva nunca puede exceder el monto (bps <= 10000).
        assertLe(lote.reservaTecnicaUSDC, montoUSDC, "reserva nunca excede el monto");

        // Balance / supply actualizados por el mint.
        assertEq(
            assetVault.balanceOf(BUYER_1, FUZZ_LOTE_ID), balanceBefore + cantidadTokens, "balance += cantidadTokens"
        );
        assertEq(assetVault.totalSupply(FUZZ_LOTE_ID), supplyBefore + cantidadTokens, "supply += cantidadTokens");
    }

    /// @dev La reserva técnica acumula linealmente entre múltiples compras del mismo lote:
    ///      tras N compras, reservaTecnicaUSDC == sum(montoUSDC_i * bps / 10_000) y
    ///      montoNetoPendiente == sum(montoUSDC_i) - reservaTecnicaUSDC.
    ///      Verifica además: reserva + neto == totalPagado siempre que NO haya release intermedio.
    function testFuzz_comprar_AcumulaReservaYNeto_AcrossCompras(
        uint256 tokens1,
        uint256 tokens2,
        uint256 precioPorTokenUSDC,
        uint16 reservaBps
    ) public {
        reservaBps = uint16(
            bound(reservaBps, ComplianceConstants.RESERVA_TECNICA_BPS_MIN, ComplianceConstants.RESERVA_TECNICA_BPS_MAX)
        );
        precioPorTokenUSDC = bound(precioPorTokenUSDC, 1, 1_000_000 * 1e6);

        // kgEsperados=100 ⇒ cap total = 200 tokens. Repartimos entre dos compras de modo que la suma <= 200.
        tokens1 = bound(tokens1, 1, 199);
        tokens2 = bound(tokens2, 1, 200 - tokens1);

        _crearLoteFuzz(FUZZ_LOTE_ID, 100, precioPorTokenUSDC, reservaBps);
        _setupKYC(BUYER_1, 1);
        _setupKYC(BUYER_2, 1);

        uint256 monto1 = tokens1 * precioPorTokenUSDC;
        uint256 monto2 = tokens2 * precioPorTokenUSDC;

        // Act — dos compras (distintos buyers, mismo lote en PREVENTA).
        _comprarFuzz(FUZZ_LOTE_ID, BUYER_1, tokens1, monto1);
        _comprarFuzz(FUZZ_LOTE_ID, BUYER_2, tokens2, monto2);

        // Assert — acumulación exacta. La reserva se computa por compra (floor independiente).
        uint256 reserva1 = (monto1 * reservaBps) / ComplianceConstants.BPS_DENOMINATOR;
        uint256 reserva2 = (monto2 * reservaBps) / ComplianceConstants.BPS_DENOMINATOR;
        uint256 reservaTotal = reserva1 + reserva2;
        uint256 netoTotal = (monto1 - reserva1) + (monto2 - reserva2);

        IAssetVault.LoteMiel memory lote = assetVault.lotes(FUZZ_LOTE_ID);
        assertEq(lote.reservaTecnicaUSDC, reservaTotal, "reserva acumulada == suma de reservas por compra");
        assertEq(lote.montoNetoPendiente, netoTotal, "neto acumulado == suma de netos por compra");
        assertEq(
            lote.reservaTecnicaUSDC + lote.montoNetoPendiente,
            monto1 + monto2,
            "reserva + neto acumulados == total pagado"
        );
    }

    // ============================================================================
    // reembolsarLoteFallido — reembolso proporcional
    // ============================================================================

    /// @dev Propiedad de `reembolsarLoteFallido` / `_refundBuyer`:
    ///        totalDisponible = montoNetoPendiente + (reservaTecnicaUSDC - reservaTecnicaLiberada)
    ///        reembolso(buyer) = totalDisponible * balance(buyer) / totalSupply   (floor)
    ///      Verifica que para cada comprador el reembolso recibido coincide con la fórmula (floor),
    ///      y que la suma de reembolsos NUNCA excede el pool (no over-refund / no draining).
    ///      Como el lote FALLA en PREVENTA, totalDisponible == 100% de lo pagado por ambos buyers.
    function testFuzz_reembolsarLoteFallido_ProporcionalYNoExcedePool(
        uint256 tokens1,
        uint256 tokens2,
        uint256 precioPorTokenUSDC,
        uint16 reservaBps
    ) public {
        reservaBps = uint16(
            bound(reservaBps, ComplianceConstants.RESERVA_TECNICA_BPS_MIN, ComplianceConstants.RESERVA_TECNICA_BPS_MAX)
        );
        precioPorTokenUSDC = bound(precioPorTokenUSDC, 1, 1_000_000 * 1e6);

        // Ambos buyers compran en PREVENTA; suma de tokens <= 200 (cap de kgEsperados=100).
        tokens1 = bound(tokens1, 1, 199);
        tokens2 = bound(tokens2, 1, 200 - tokens1);

        // Arrange
        _crearLoteFuzz(FUZZ_LOTE_ID, 100, precioPorTokenUSDC, reservaBps);
        _setupKYC(BUYER_1, 1);
        _setupKYC(BUYER_2, 1);

        uint256 monto1 = tokens1 * precioPorTokenUSDC;
        uint256 monto2 = tokens2 * precioPorTokenUSDC;

        _comprarFuzz(FUZZ_LOTE_ID, BUYER_1, tokens1, monto1);
        _comprarFuzz(FUZZ_LOTE_ID, BUYER_2, tokens2, monto2);

        // Pool reembolsable = monto neto en escrow + reserva no liberada. Pre-cosecha == total pagado.
        IAssetVault.LoteMiel memory loteFallido = assetVault.lotes(FUZZ_LOTE_ID);
        uint256 totalDisponible =
            loteFallido.montoNetoPendiente + (loteFallido.reservaTecnicaUSDC - loteFallido.reservaTecnicaLiberada);
        assertEq(totalDisponible, monto1 + monto2, "pool pre-cosecha == 100% de lo pagado");

        uint256 totalSupplyLote = assetVault.totalSupply(FUZZ_LOTE_ID);
        assertEq(totalSupplyLote, tokens1 + tokens2, "supply == suma de tokens comprados");

        // Reembolsos esperados por la fórmula del contrato (floor).
        uint256 esperado1 = (totalDisponible * tokens1) / totalSupplyLote;
        uint256 esperado2 = (totalDisponible * tokens2) / totalSupplyLote;

        // Act — marcar fallido y reembolsar a ambos.
        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(FUZZ_LOTE_ID, "fallo pre-cosecha fuzz");

        uint256 bal1Before = usdc.balanceOf(BUYER_1);
        uint256 bal2Before = usdc.balanceOf(BUYER_2);

        address[] memory buyers = new address[](2);
        buyers[0] = BUYER_1;
        buyers[1] = BUYER_2;

        vm.prank(ORACLE_SAFE);
        assetVault.reembolsarLoteFallido(FUZZ_LOTE_ID, buyers);

        // Assert — cada reembolso coincide con la fórmula proporcional (floor).
        uint256 recibido1 = usdc.balanceOf(BUYER_1) - bal1Before;
        uint256 recibido2 = usdc.balanceOf(BUYER_2) - bal2Before;
        assertEq(recibido1, esperado1, "reembolso BUYER_1 == totalDisponible*balance/supply (floor)");
        assertEq(recibido2, esperado2, "reembolso BUYER_2 == totalDisponible*balance/supply (floor)");

        // No over-refund: la suma de reembolsos nunca excede el pool disponible.
        assertLe(recibido1 + recibido2, totalDisponible, "suma de reembolsos <= pool (no draining)");

        // Tokens quemados — ambos buyers a 0.
        assertEq(assetVault.balanceOf(BUYER_1, FUZZ_LOTE_ID), 0, "BUYER_1 quemado a 0");
        assertEq(assetVault.balanceOf(BUYER_2, FUZZ_LOTE_ID), 0, "BUYER_2 quemado a 0");
    }

    /// @dev Un único comprador que posee el 100% del supply recibe EXACTAMENTE el pool completo
    ///      (totalDisponible * supply / supply == totalDisponible, sin pérdida por rounding).
    function testFuzz_reembolsarLoteFallido_SingleBuyerRecibeTodoElPool(
        uint256 cantidadTokens,
        uint256 precioPorTokenUSDC,
        uint16 reservaBps
    ) public {
        reservaBps = uint16(
            bound(reservaBps, ComplianceConstants.RESERVA_TECNICA_BPS_MIN, ComplianceConstants.RESERVA_TECNICA_BPS_MAX)
        );
        precioPorTokenUSDC = bound(precioPorTokenUSDC, 1, 1_000_000 * 1e6);
        cantidadTokens = bound(cantidadTokens, 1, 200);

        _crearLoteFuzz(FUZZ_LOTE_ID, 100, precioPorTokenUSDC, reservaBps);
        _setupKYC(BUYER_1, 1);

        uint256 monto = cantidadTokens * precioPorTokenUSDC;
        _comprarFuzz(FUZZ_LOTE_ID, BUYER_1, cantidadTokens, monto);

        IAssetVault.LoteMiel memory lote = assetVault.lotes(FUZZ_LOTE_ID);
        uint256 totalDisponible = lote.montoNetoPendiente + (lote.reservaTecnicaUSDC - lote.reservaTecnicaLiberada);

        vm.prank(ORACLE_SAFE);
        assetVault.marcarFallido(FUZZ_LOTE_ID, "fallo single buyer fuzz");

        uint256 balBefore = usdc.balanceOf(BUYER_1);

        address[] memory buyers = new address[](1);
        buyers[0] = BUYER_1;
        vm.prank(ORACLE_SAFE);
        assetVault.reembolsarLoteFallido(FUZZ_LOTE_ID, buyers);

        // Único holder ⇒ recibe el pool íntegro == monto pagado (no rounding loss).
        assertEq(usdc.balanceOf(BUYER_1) - balBefore, totalDisponible, "single buyer recibe el pool completo");
        assertEq(totalDisponible, monto, "pool == 100% de lo pagado (pre-cosecha)");
    }
}
